# Decision Log

Append-only record of notable engineering decisions. Newest at the bottom.

## 2026-07-23 — Vision collapsed to Claude-only, default Sonnet 5

Context: The pipeline had drifted across providers (Groq Llama-4 → qwen3.6 →
OpenAI gpt-5.2) chasing a reliable vision model. An eval on 15 N5k dishes
compared gpt-5.2, Claude Sonnet 5, and Haiku 4.5.
Decision: Remove the OpenAI and Groq code paths; use Anthropic's native
Messages API with structured outputs, default model `claude-sonnet-5`
(`RIVA_SCAN_MODEL` overrides).
Rationale: The VLM is only an identifier (portion/macros are deterministic
downstream), so ID quality + speed decide it. Sonnet 5 matched gpt-5.2 on
dish-name ID, beat it on ingredient recall (53% vs 48%) and FDC grounding (73%
vs 67%), at ~3× the speed (p50 8.4s vs ~25s). Haiku 4.5 dropped ~20 pts on ID
and hallucinated on lab images, so it was rejected as default. Still local/
uncommitted; prod stays on gpt-5.2 until the mirror is pushed + Manual Deploy.

## 2026-07-22 — `/v1/scan` made public and anonymous

Context: The public web scanner needed to work without a sign-in flow.
Decision: Remove auth from `/v1/scan`; the web page writes nothing to the DB
(never calls `/v1/log`). Persistence stays behind authenticated `/v1/log`,
which only the iOS app uses.
Rationale: The web page is a test tool; the iOS app is the product. Accepted
cost tradeoff: an open anonymous endpoint on paid keys. Rate-limiting is a
possible follow-up.

## 2026-07-20 — Do not fine-tune on Nutrition5k yet

Context: V1 (gpt-5.2 + USDA) on 15 N5k dishes showed calorie MAPE ~43% with
systematic under-estimation on dense plates.
Decision: Do not fine-tune on N5k. Fix USDA grounding (e.g. the parenthesis 400
bug) and real-photo capture first; build a real-phone-photo eval set.
Rationale: N5k is top-down lab-rig imagery — a domain gap vs. phone photos, so
its numbers are a pessimistic floor. Fitting to it risks optimizing for the
wrong distribution.

## 2026-07-22 — Deploy via a mirror repo with auto-deploy off

Context: Render was configured to watch a separate repo, and accidental pushes
had shipped unintended changes.
Decision: Ship backend changes only by pushing the `Riva-Snap` mirror
(`backend/.git-snap`) and then clicking Manual Deploy on Render; keep
auto-deploy OFF. Pushing `Riva-App` never deploys.
Rationale: A manual gate prevents accidental production deploys and keeps
local-first testing the norm.

## 2026-07-22 — Volumetric redesign Phase-0: single-view depth is insufficient

Context: Before building the v2 "Riva Scan" volumetric pipeline (SAM 2 + Depth
Anything V2 + volume engine on serverless GPU), de-risked the core claim with a
~150-line numpy prototype (`eval/volumetric/`): does integrating a depth map over
a food mask predict mass? Tested on 15 N5k dishes using ground-truth depth to
isolate geometry from the depth model.
Decision: Do NOT stand up the GPU monocular tier yet. Treat the ARKit metric
multi-view path as REQUIRED (not a fallback), and build a real multi-view +
weighed-mass eval set before further pipeline work.
Rationale: R²(GT mass, depth-volume) = 0.16 and leave-one-out grams MAPE ~90% —
far worse than the V1 LLM's ~23%, even in the best case (GT depth, isolated food
mound). R² is scale-invariant, so intrinsics/density/scale tuning cannot rescue
it: a single top-down frame lacks the shape signal (confirms the doc's pain-point
#2). N5k is top-down-only and cannot validate the multi-view redesign, so the fair
test is real phone arc-video capture with kitchen-scale ground truth. See
`eval/volumetric/FINDINGS.md`.

## 2026-07-23 — Multi-item / multi-view volumetric: fusion + plausibility gate

Context: Extended the tap-and-hold flow to multiple items and N views. The current
flow was single-item, single-blob, single-frame; the redesign doc measures one
total volume and splits by LLM ratios (the §11 gap).
Decision: (1) Fusion = **per-view estimate + confidence-weighted geometric mean**,
NOT silhouette space-carving — carving needs calibrated per-view poses we don't have
on uncalibrated phone photos; it's the ARKit-era upgrade. Degrades to N=1 with a
confidence penalty (a hard requirement). (2) Scale = published dimensions as a PRIOR
only, seeded from the food-class footprint and refined per class — never ground
truth. (3) A **required plausibility gate** runs before anything logs: volume→mass→
kcal validated against a per-class range (`food_classes.json`, `_generic` fallback);
in-range logs, mild out-of-range clamps + low-confidence, >3x out prompts retake.
Never logs the raw value.
Rationale: uncalibrated RGB + no depth rules out carving; the gate stops error-
stacking (volume×density×kcal) from silently logging garbage. Multi-item per-item
volume still needs SAM 2 masks (currently splits total by LLM ratio). LogMeal noted
as a future reference for multi-item segmentation, not a dependency. See
`eval/volumetric/multiview/README.md`.

## 2026-07-23 — Plausibility gate folded into the shipping V1 scan

Context: The V1 scanner logged the LLM's raw portion grams, which can be wildly
off (a 2 kg burger). The volumetric pipeline is still gated on the eval bench, but
the gate logic is useful in production today.
Decision: `_assemble` now runs every scan item through `app/plausibility.py` before
totals/delta. Grams are validated against a per-class mass range (derived from
`app/food_classes.json` volume x density); out-of-range grams are clamped to the
bound, macros scaled by the clamp factor, confidence lowered, and a new
`ScanItem.plausibility` field set to "ok" | "clamped" | "implausible". Nothing raw
out-of-range is ever logged. `app/food_classes.json` is the single canonical class
table (the multiview prototype reads it too).
Rationale: cheap accuracy guardrail with no infra; stops the error-stacking from
silently logging garbage. Contract change: `ScanItem` gains `plausibility`
(defaults "ok", backward compatible). Bounds are conservative (wide _generic
fallback) to avoid false clamps.

## 2026-07-23 — B1 volumetric carver: plumbing proven, accuracy unproven

Context: Phase-0 (`eval/volumetric/FINDINGS.md`) showed single-view depth-volume 
R²=0.16 against ground-truth depth (far below the R²≥0.6 GO gate). Multi-view 
ARKit-metric geometry is the path forward (see 2026-07-23 fusion decision). B1 
implements end-to-end plumbing with a calibrated visual-hull carver for tiers 
A/B (ARKit pose+intrinsics present) and a parametric fallback for tier C (no 
ARKit). Verifier PASS at 96% on synthetic geometry.
Decision: Space-carving is enabled, but ONLY for the calibrated ARKit path 
(tiers A/B where camera-to-world pose and intrinsics are supplied per-frame). 
For tier C (uncalibrated phone RGB, no poses), the parametric class-prior 
estimate (`geometry.fuse`) is used. Carving never fails the request — a carve 
exception degrades to parametric, never 500s. The volume gate then validates 
the result against the class's plausible range, independent of the geometry 
path taken.
Rationale: Phase-0 rejected space-carving for uncalibrated 2D photos because 
poses were absent. ARKit metric pose IS that calibration — it makes visual-hull 
carving geometrically sound. Uncalibrated RGB alone has no metric reference and 
cannot benefit from multi-view carving (no parallax calibration), so the 
parametric fallback is the only option. Graceful degradation (not a 500) is 
required because real capture may occasionally fail to produce valid poses or 
sufficient views.
Gating: The volume gate and downstream mass plausibility gate (`_assemble`) are 
both enforced (defense-in-depth). Real-world accuracy is gated on step 6 
(weighed ARKit captures): GO = R²≥0.6 AND grams MAPE≤20% vs the v1 baseline 
~23%. Real carve accuracy on food (vs synthetic masks) is yet to be validated. 
See `backend/app/volumetric/carve.py` for the coordinate convention and caveats: 
the 2-view occupancy test degrades to union; the support plane is a gravity-aligned 
heuristic (pending real plane serialization from ARKit).

## 2026-07-24 — V3 segmentation performance: downscale-then-upscale unblocks real-device validation

Context: Real-device testing on a tier-B iPhone 17 (ARKit poses, no LiDAR) using the 
B1 carver pipeline revealed classical GrabCut executed on full-resolution ARKit frames 
(~1920×1080+) took ~35s per frame. Sequential processing of 6 captured frames ran 
~212s total, exceeding the iOS client's 120s `timeoutIntervalForRequest` — every 
multi-frame volumetric capture failed with "could not reach the scan service."
Decision: `backend/app/volumetric/geometry.py` — `segment_food()` now downscales each 
frame to a working resolution (longest side clamped to `SEG_MAX_SIDE = 512`, using 
`cv2.INTER_AREA`) before running GrabCut segmentation, then nearest-neighbour upscales 
the resulting boolean mask back to full resolution. Frames already ≤512px are unchanged 
(scale factor clamps to 1.0). The return contract is preserved: a full-size bool mask, 
or None on failure.
Rationale: Downscaling reduces GrabCut per-frame time from ~35s to ~572ms (61x speedup). 
A real 6-frame capture now completes end-to-end (identify 6.2s + segment 20.8s + carve + 
log ~27s total), well within the 120s timeout. Per-frame downscaling is geometrically sound 
for silhouette extraction (GrabCut solves per-frame, mask shape is scale-invariant when 
upscaled). Contract-preserving: callers receive a full-res mask regardless of internal 
downscaling. Regression tests (3 cases: large-frame downscale path, small-frame unchanged 
path, degenerate) added to `backend/tests/test_volumetric_geometry.py`; full volumetric 
suite: 25 passed.
Real-device findings: Two accuracy failure modes observed across captures, both pointing at 
segmentation quality and grid sizing as the open levers (NOT resolution downscaling): 
(1) Capture A: visual-hull volume 242.5 ml, but hull hit the 0.10 m carve grid boundary 
(`carve.grid_boundary_hit = True`), volume likely clipped — grid too coarse for real plated 
portions. (2) Capture B: volume 45.4 ml, clamped to plausible bound (`action=clamp`) — 
undersegmented / partial silhouette, clamped by the plausibility gate. Both errors upstream 
of the carving step. Accuracy validation (R²≥0.6, grams MAPE≤20%) remains the GO gate; 
grid sizing + segmentation quality are the next tuning knobs.

## 2026-07-28 — Email + password as the third provider, no credential store of our own

Context: Riva needed an email/password option beside Google and Apple, with an
emailed OTP confirming the address before a password is chosen, and a reset
path. The original ask included storing the password unencrypted so it could be
read back.
Decision: Build it entirely client-to-GoTrue. Passwords are set via
`PUT auth/v1/user` and live only as bcrypt in `auth.users.encrypted_password`.
No new backend endpoint, no `user_credentials` table, no plaintext copy. OTP and
recovery emails are sent by GoTrue with Gmail configured as custom SMTP in the
Supabase dashboard. Strength checking is on-device in `PasswordPolicy.swift`
following NIST SP 800-63B (length + blocklist, no composition rules).
Rationale: GoTrue already hashes and stores the password, so a readable copy
would have been *net-new* code — a table, a service-role endpoint, and the app
posting the raw password to our backend on top of Supabase — whose only effect
is to make GLP-1 users' passwords readable in a breach. Hashing is also not the
same thing as encryption, so "skip the crypto for now" costs nothing here: the
secure path is the zero-work path. Custom SMTP is dashboard configuration
rather than a backend mailer for the same reason — GoTrue owns the send.
Consequence: **Supabase custom SMTP must be configured or codes will not
arrive** — GoTrue's shared sender is heavily rate-limited. Gmail also caps
~500 sends/day, so a transactional provider (Resend / SendGrid / Postmark) is
the eventual move.

## 2026-07-28 — Custom Sign in with Apple button so the three providers share one font

Context: On the onboarding and login screens the Google, Apple, and email
buttons stack together. `SignInWithAppleButton` draws its own SF Pro label
sized to the frame, so the middle button read as a different typeface at a
larger size than the DM Sans Bold 15 on either side of it. There is no API to
restyle the system control's title.
Decision: Replace it with a custom `AppleSignInButton` — black capsule, white
`apple.logo` and title in `TPCFont.bodyBold` — driven by a new
`AppleAuthSession` wrapper around `ASAuthorizationController`. The nonce
handshake and `AuthModel.completeAppleSignIn(_:fromLogin:)` are unchanged; only
the control that starts the request is ours.
Rationale: Apple permits a custom Sign in with Apple button provided it keeps
the Apple logo, one of the approved titles ("Sign in with Apple" / "Sign up
with Apple", enforced by the `Title` enum), sufficient contrast, and prominence
equal to the other providers. All four hold; only the typeface changed. This
supersedes the earlier comment in `AppleSignInButton.swift` that the system
control must stay — that was about *restyling Apple's appearance*, which this
does not do.
Consequence: The Apple flow no longer gets Apple's own button behaviour for
free. If App Review ever objects, reverting is `SignInWithAppleButton` back in
the button body — `AppleAuthSession` is the only other file involved and
`AuthModel` needs no change either way.
