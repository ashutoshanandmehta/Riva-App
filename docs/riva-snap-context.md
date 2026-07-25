# Riva Snap — Internal Context & Working Notes

_Internal reference for the Riva project (The Peptide Company). Compiled 2026-07-22.
Covers architecture, deployment, the scan service, evals, the redesign, ownership, and gotchas._

---

## 0. TL;DR (the things that bite you)

1. **Deployment is via a SEPARATE repo.** Render deploys `Riva-Snap`, not `Riva-App`. Pushing `Riva-App` does nothing to production. You must push the **mirror** at `backend/.git-snap` (see §2).
2. **Render auto-deploy is OFF.** After pushing the mirror, click **Manual Deploy → Deploy latest commit**.
3. **Vision provider is Claude only** (local code): the OpenAI/Groq paths were removed — `app/vision.py` uses the Anthropic Messages API, default `claude-sonnet-5` (override via `RIVA_SCAN_MODEL`). Needs `ANTHROPIC_API_KEY`. The VLM is an *identifier only* (portion/volume is deterministic downstream), so a perception-tier model suffices. **NOTE:** this is **local/uncommitted** — production is still the old code on OpenAI `gpt-5.2` until the mirror is pushed + Manual Deploy.
4. **Never commit/push without explicit permission.** Test locally first.
5. **N5k eval numbers are a pessimistic floor** (top-down lab images ≠ real phone photos).

---

## 1. What Riva is

- **Riva** — a GLP-1 companion app by **The Peptide Company** (US digital-healthcare / peptide startup, pre-seed, stealth).
- Two parts: a native **iOS app** (SwiftUI) and a **food-scanning backend** ("Riva Snap").
- Core feature: photo → nutrition (dish, portion, calories, macros).
- Repo root on disk: `/Users/ashutoshanand/Downloads/Riva`, laid out as:
  - `ios/` — the SwiftUI app (`Riva.xcodeproj`, `Riva/`)
  - `backend/` — the FastAPI scan service (`app/`, `web/`, `eval/`, `prompts/`, `render.yaml`, `supabase/`)
  - `docs/` — diagrams + this doc

---

## 2. Repositories & deployment  ← READ FIRST

**Two GitHub repos:**

| Repo | Purpose |
|---|---|
| `github.com/ashutoshanandmehta/Riva-App` | The monorepo (`ios/` + `backend/`). `origin` of the working tree. **Pushing here does NOT deploy.** |
| `github.com/ashutoshanandmehta/Riva-Snap` | The **deploy mirror** Render watches. Backend content sits at its repo root. |

- The mirror's git metadata lives at **`backend/.git-snap`** — a separate git dir whose work-tree is `backend/` (gitignored via `backend/.git-snap/`).
- **To ship a backend change, push the mirror:**
  ```bash
  cd backend
  GD="$PWD/.git-snap"; WT="$PWD"
  git --git-dir="$GD" --work-tree="$WT" add app/main.py web/... render.yaml   # specific files
  git --git-dir="$GD" --work-tree="$WT" commit -m "..."
  git --git-dir="$GD" --work-tree="$WT" push origin main
  ```
- Keep downloaded/generated eval data OUT of the mirror (`.git-snap/info/exclude` has `eval/n5k_cache/`, `eval/golden.n5k.jsonl`, `eval/images/n5k_*.png`, `eval/reports/`).

**Render:**
- Service **`riva-snap`**, live at **https://riva-snap.onrender.com**.
- **Free tier**: CPU-only, 512 MB RAM, spins down on inactivity. A **5-minute cron** keeps it warm to avoid cold starts.
- **Auto-deploy is OFF** → after a mirror push, **Manual Deploy → Deploy latest commit**.
- `render.yaml` is the blueprint (Blueprint-managed). Declares env vars as `sync: false` secrets: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GROQ_API_KEY`, `FDC_API_KEY`, `SUPABASE_URL/ANON/SERVICE_ROLE`, `RIVA_SCAN_DEBUG`, `PYTHON_VERSION`.

**Current git state (as of writing):**
- `Riva-App` main @ `7b5f027`
- `Riva-Snap` main @ `6566453`
- The **V2 / CalorieMama work is local & uncommitted** (deliberately not pushed — see §6).

---

## 3. Backend — the scan service

- FastAPI at `backend/app/main.py`. Static web served at `/` from `backend/web/`.
- **Claude-only vision** (`app/vision.py`): `make_client()` builds an `anthropic.Anthropic` client from `ANTHROPIC_API_KEY`; `resolve_model()` returns `RIVA_SCAN_MODEL` or the `claude-sonnet-5` default. OpenAI/Groq paths were **removed** (2026-07-23) to keep one clean path.
  - Native **Messages API** (not the OpenAI shim) via the `anthropic` SDK, with **structured outputs** (`output_config.format` + `SCAN_SCHEMA`) so the strict-JSON contract holds. Thinking is **disabled** (perception task; Haiku just omits it — it predates the option). Override the model via `RIVA_SCAN_MODEL` (e.g. `claude-opus-4-8` for quality; Haiku evaluated poorly, see §7). `SCAN_SCHEMA`'s `type:[X,"null"]` unions are auto-rewritten to `anyOf` for Claude (`_nullable_to_anyof`) — one schema source.
  - **Prod is still OpenAI `gpt-5.2`** (old deployed code) — the Claude rewrite is local/uncommitted. To ship: set `ANTHROPIC_API_KEY` in Render env (done), push the mirror, Manual Deploy, then `curl /healthz` → `{"provider":"anthropic","model":"claude-sonnet-5",...}`.
  - History: started on Groq; Groq **retired Llama-4 vision** → fell to `qwen3.6` (slow); switched to OpenAI `gpt-5.2` for reliability; then **collapsed to Claude-only** (Sonnet 5 matched gpt-5.2 on ID, ~3× faster — see §7).
- **Config** (`app/config.py`): pydantic-settings from env/`.env`. All keys whitespace-stripped (dashboards add line-wraps).
- **USDA grounding**: `app/fdc.py` (FoodData Central search, per-100g nutrients) + `app/grounding.py` (`best_match`, `grounded_nutrients`). `FDC_API_KEY` is set (real key). **Known bug: FDC search returns 400 on parenthetical queries** e.g. `"Roasted sweet potato (with oil)"`.

**Key endpoints:**

| Endpoint | Notes |
|---|---|
| `POST /v1/scan` | gpt-5.2 → structured JSON → USDA grounding. **Now anonymous** (auth removed) so the public web scanner works. Stateless, no DB write. |
| `POST /v1/log`, `/v1/log/{weight,shot,side-effects,checkin}` | Authenticated; write to Supabase. |
| `POST /v1/device/session` | Mints a Supabase session for a `device_id`. Used to bypass Google sign-in in the simulator. |
| `GET /healthz`, `/v1/config`, `/v1/dashboard`, `/v1/me`, `/v1/weights`, `/v1/export`, … | Health, client bootstrap, account/dashboard reads. |
| `POST /v2/scan` | **NEW, local/uncommitted** — proxies to CalorieMama (see §6). |

---

## 4. Web frontends (`backend/web/`)

- **Public scanner** — `index.html`, served at `/`. Sign-in was **removed**; it's a **public, no-auth test tool**, open to all, that **writes nothing to the DB** (never calls `/v1/log`). Posts to `/v1/scan` (anonymous). Deliberate decision: the web page is a test tool; the iOS app is the real product.
  - ⚠️ Cost note: `/v1/scan` is now an open anonymous endpoint on the paid OpenAI key — anyone with the URL can spend. Acceptable for now per the owner; rate-limiting is a possible follow-up.
- **Riva Snap V2** — `v2.html`, served at `/v2.html` (**local/uncommitted**). Fresh calm design (sage-white / clementine, Bricolage Grotesque + Space Mono), drag/drop + camera, lock-reticle preview, "Top match" + "Not quite? It might be…". Posts to `/v2/scan`. See §6.

---

## 5. iOS app

- SwiftUI. Bottom tabs: **Home** (dashboards), **Wellness** (check-ins), **Snap** (scanner), **Medication** (dose + pharmacokinetic curve, "Log Weekly Shot", dose history), **Tracker** (weight / side-effects).
- Bundle id **`in.riva`**, signing team **`TCW3JM44ZF`**.
- **Mandatory Google sign-in** at launch (can't complete OAuth in the simulator).
- **Debug launch args** (bypass auth / drive the app): `-riva.accessToken` / `-riva.refreshToken` (inject a session), `-riva.tab`, `-riva.snapMenuOpen`, `-riva.scanTestImage`, `-riva.scanAutoAccept`, `-riva.auth`, `-riva.accountSheet`, `-riva.detail`, `-riva.appearance`.
- The wired auth repo is `SupabaseAuthRepository` (reads the injected token from launch args).

**Run signed-in in the simulator:**
```bash
# build (build/ is gitignored)
xcodebuild -project ios/Riva.xcodeproj -scheme Riva -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
xcrun simctl boot "iPhone 17 Pro"; open -a Simulator
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Riva.app
# mint a token:
#   curl -s -X POST https://riva-snap.onrender.com/v1/device/session \
#     -H "Content-Type: application/json" -d '{"device_id":"sim-demo-0001"}'
xcrun simctl launch booted in.riva -riva.accessToken <AT> -riva.refreshToken <RT>
xcrun simctl io booted screenshot out.png
```

---

## 6. Riva Snap V2 — CalorieMama (local/uncommitted)

- Endpoint: `https://caloriemama.ai/api/food_recognition_proxy`.
- **It needs NO API key.** It gates on **Referer/Origin** headers (it powers CalorieMama's own web demo):
  `Referer: https://caloriemama.ai/`, `Origin: https://caloriemama.ai`.
  (The undefined `HEADERS` in the original Colab snippet was this Referer/Origin spoof, not an auth key.)
- **A browser cannot call it directly** — the endpoint sends **no `Access-Control-Allow-Origin`**, so CORS blocks reading the response. That's why the `/v2/scan` server-side proxy exists (server→server has no CORS + adds the headers). `mode:"no-cors"` doesn't help (opaque, unreadable).
- **The `/v2/scan` proxy** (in `app/main.py`, uncommitted): reads the image, resizes to 544×544 JPEG, POSTs to CalorieMama with the Referer/Origin headers, returns the JSON. No key/env needed.
- **Response shape**: `results[].items[]` with `name`, `score` (a relevance RANK, not a probability — can be >100), `nutrition {calories, protein, totalCarbs, totalFat}`, `servingSizes`.
- **Nutrition is unreliable & not portion-aware.** Examples: "Momo" → 1667 kcal with 0g protein/carbs/fat; "Duck Neck" → 1200/0/0/0. The number is fixed per food type regardless of how much is on the plate. **Good for identification, useless for macros.**
- **Verdict:** CalorieMama = a fast food *namer* (strong on real phone photos), not a nutrition source. Best possible architecture: **CalorieMama name → USDA grounding** for real macros.

---

## 7. Evaluation (Nutrition5k)

Tooling in `backend/eval/`:
- `n5k_to_golden.py` — downloads Nutrition5k over plain HTTPS (bucket path is **doubly nested**: `https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset/…`), samples held-out `rgb_test` dishes, writes `golden.n5k.jsonl` (kcal, grams, macros, ingredients, dominant dish). Stdlib only.
- `run_eval.py` — runs the V1 pipeline over a golden set; extended to score **portion gram MAPE** + **ingredient recall** (`--golden/--images/--limit`).
- `eval_caloriemama.py` — CalorieMama identification eval.
- `compare_v1_v2.py` — V1 vs V2, both USDA-grounded, per-100g density.

**Golden set = 15 held-out N5k dishes.**
**Caveat throughout:** N5k images are top-down lab-rig shots (with depth sensors), a domain gap vs real phone photos → all numbers are a **pessimistic floor**.

**V1 (gpt-5.2 + USDA), 15 dishes:**
- dish-name ~80%, ingredient recall 48%, scan_type 100%
- **calorie MAPE 43%** (systematic UNDER-estimation on dense plates), **portion gram MAPE 23%**
- FDC match 67%, latency ~25s p50
- → Decision: **don't fine-tune on N5k yet** (domain gap); fix grounding + capture first.

**Claude vs gpt-5.2 (same 15 N5k dishes, run 2026-07-23):**
| Metric | gpt-5.2 | **Sonnet 5** | Haiku 4.5 |
|---|---|---|---|
| Dish-name match | ~80% | 73% | 53% |
| Ingredient recall | 48% | **53%** | 35% |
| FDC match | 67% | **73%** | 53% |
| Calorie MAPE | 43% | 37% | 72% |
| Portion-gram MAPE | 23% | 31% | 59% |
| Latency p50 | ~25s | **8.4s** | 5.5s |
- The VLM is an *identifier* (portion/macros become deterministic downstream), so the top 3 rows decide it. **Sonnet 5 matches gpt-5.2 on ID, beats it on ingredient recall + grounding, ~3× faster** → **chosen default** (`claude-sonnet-5`). **Haiku 4.5 fails** — ~20-pt ID drop, hallucinates on lab images (steak→"potato wedges", watermelon→"fried shrimp"); re-test only on a real-phone-photo set. Numbers still a pessimistic floor (N5k domain gap).

**CalorieMama (v2), 15 dishes:**
- is_food 93%, dominant-ingredient-in-top-5 **20%**, any-ingredient **33%**, ingredient recall **11%**
- Poor ID on lab images (steak→Duck Neck, watermelon→Scrambled Egg, chicken→Mantu). **Strong on real photos** (momo scan nailed it).

**V1 vs V2, both USDA-grounded, per-100g calorie density:**
| | V1 (gpt-5.2 + USDA) | V2 (CalorieMama + USDA) |
|---|---|---|
| per-100g cal MAPE | **34%** | **180%** |
| produced a grounded number | **15/15** | **6/15** |
- **V1 wins ~5x.** CalorieMama's misIDs don't ground in USDA (9/15 produced nothing). Grounding doesn't rescue a bad identifier.

**Reference base rates (literature):** trained systems on N5k ~11–16% calorie MAPE; monocular food-volume methods ~16–31% MAPE; a trained RGB-only transformer ~13.5% (beats several depth methods).

---

## 8. The redesign ("Riva Snap Redesigned") — TARGET, not built

Design doc (`Riva snap (redesigned) v2.docx`) + diagrams in `docs/`. **None of the vision tier is built.**

**Pipeline (target):** tap-to-anchor + 3–5s "arc" video → on-device preprocess (720p, extract 15 frames, Laplacian blur filter, keep best 5–6, **upload images only, not video**) → FastAPI orchestration agent → **parallel vision**: SAM 2 (segment/track food mask), YOLOv11 (scale-anchor object), Depth Anything V2 (relative depth) → **volumetric engine** (mask×depth → metric scale → integrate → volume mL) → multimodal LLM (ingredient %) → density DB (volume→grams) → USDA macros → **human approval**.

**Two depth strategies (device-dependent):**
- **ARKit path (preferred):** capture metric camera pose per frame → true metric structure-from-motion, no reference object needed.
- **Default path:** Depth Anything V2 monocular + scale from a container preset or a YOLO-detected reference object; multi-view used to (1) constrain monocular scale/shift, (2) silhouette-carve the pile from SAM 2 masks, (3) read pile height from side/45° frames.

**Feasibility (with current resources):**
- ~2/3 buildable now: iOS capture + ARKit pose, on-device preprocessing, FastAPI orchestration, the LLM step, USDA, the volume math.
- **The vision tier (SAM 2 + Depth Anything V2) needs a GPU** — Render free tier (CPU, 512 MB) can't run it. Use **serverless GPU** (Replicate / Modal / Fal) for cents/call — no owned hardware.
- **The real research risk is metric volume from monocular depth** (scale/shift ambiguity). ARKit sidesteps it; the default path is harder.

**Diagrams in `docs/`:** `scan-pipeline.{mmd,png}` (detailed 6-scene user flow), `scan-architecture.{mmd,png}` (plain-language), `scan-diagrams.md` (both, editable Mermaid). Render Mermaid → PNG locally via `npx @mermaid-js/mermaid-cli`.

---

## 9. Ownership & access (co-ownership model)

- Company entity: **The Peptide Company** — company account **thepeptidecompany90@gmail.com**. Founder's Supabase login: **aashutosh22@iitk.ac.in**.
- Model: **co-ownership (shared access), NOT handover** — add the company account as co-owner/admin, keep the personal account.

| Service | Status |
|---|---|
| **Supabase** (org "Riva", ref `casmdqfgxoihjisrjsbk`) | ✅ both Owners. A co-owner change keeps ref/URL/keys → **no re-pointing** of Render/app. |
| **GitHub** (Riva-App + Riva-Snap) | ✅ company added as **Admin collaborator**; repos stay under `ashutoshanandmehta` so Render's deploy link is intact. |
| **Render** (`riva-snap`) | ⏸️ member invites need a **paid Team plan** (deferred). Service is reproducible from repo + `render.yaml` + secrets, so not locked in. |
| **OpenAI** | ⬜ invite company to the OpenAI org (decide whose card pays). |
| **Apple Developer** | ⬜ later — needs an **org account + D-U-N-S** (slow; only for App Store). |

---

## 10. Gotchas / lessons learned

- **Deploy:** push the **Riva-Snap mirror**, not just Riva-App; then **Manual Deploy** (auto-deploy OFF). This caused the most confusion.
- **Don't commit/push without explicit permission** — the owner tests locally first. (A push to both repos was reverted at their request.)
- **Groq** rotates/retires preview vision models; **OpenAI** is the stable path.
- **FDC** search 400s on parenthetical queries — grounding bug to fix.
- **CalorieMama**: Referer/Origin (no key); nutrition unreliable; browser CORS-blocked → proxy required.
- **N5k domain gap**: every eval number is a pessimistic floor; a real-phone-photo eval is the fair test.
- **Secrets hygiene**: keys go in `.env` (gitignored) + Render env, never in code or chat. Rotate anything that leaks.
- Local Python: use the `backend/.venv` (uv-managed 3.12); `requests` is NOT installed — use `httpx` / stdlib `urllib`.

---

## 11. Open threads / TODOs

- Decide fate of **V2 (CalorieMama)** — currently local/uncommitted. If shipping: push mirror + manual deploy. Consider **CalorieMama-name → USDA-grounding** as the real v2 architecture (best of both).
- **Fix the FDC parenthesis grounding bug** (cheap calorie-accuracy win).
- **Build a real-phone-photo eval set** — the fair test for CalorieMama and for the redesign.
- **Colab prototype** the volumetric pipeline cell-by-cell, with a **ground-truth success metric defined up front** (don't declare victory on "models ran").
- Complete ownership: **Render** (paid plan), **OpenAI org**, **Apple org** (start D-U-N-S early).
- Optional: rate-limit / cost-cap the public `/v1/scan` (open anonymous endpoint on paid OpenAI).
- **Per-item volumetric (redesign gap):** the current redesign measures ONE total volume then splits it by LLM-guessed ratios — it does NOT measure each item's volume. Upgrade path: per-item segmentation (SAM 2 multi-mask, seeded by a detector) → volume each item separately.
- **Candidate integrations (multi-item detection):**
  - **LogMeal** (`logmeal.com/api`) — clean multi-item detection (per-region items + candidates), food-type/food-group recognition, and calorie estimation. **Lacks volumetric analysis** → complementary: use it to localize each item, then run our volume engine per item. Best fit for the per-item gap above.
  - **CalorieMama** — fast single-dish naming (Referer/Origin proxy, unreliable nutrition). Identifier only.
  - Both are *identifiers*, not portion/volume engines. The volumetric measurement stays ours.

---

## 12. Quick command reference

```bash
# Health / provider check
curl -s https://riva-snap.onrender.com/healthz

# Run backend locally (from backend/)
.venv/bin/uvicorn app.main:app --reload --port 8000    # then http://localhost:8000/  and /v2.html

# Deploy a backend change: push the mirror, then Manual Deploy on Render
cd backend; GD="$PWD/.git-snap"; WT="$PWD"
git --git-dir="$GD" --work-tree="$WT" add <files>
git --git-dir="$GD" --work-tree="$WT" commit -m "..."
git --git-dir="$GD" --work-tree="$WT" push origin main

# Evals (from backend/)
.venv/bin/python eval/n5k_to_golden.py --n 15          # build golden set
.venv/bin/python eval/run_eval.py --golden eval/golden.n5k.jsonl   # V1 (gpt-5.2, paid)
.venv/bin/python eval/eval_caloriemama.py              # CalorieMama identification
.venv/bin/python eval/compare_v1_v2.py                 # V1 vs V2, USDA-grounded (paid)
```
