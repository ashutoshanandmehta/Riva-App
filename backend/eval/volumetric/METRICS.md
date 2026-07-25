# Volumetric pipeline — success metric (defined BEFORE building)

Per the redesign doc's Evaluation section and the project rule "define a ground-truth
success metric up front — don't declare victory on 'models ran'." This is Phase 0:
**de-risk the volume math before any GPU/iOS investment.**

## The one question Phase 0 answers
Does integrating a depth map over a food mask produce a volume that **predicts food mass
better than the current LLM estimate**? If even *ground-truth* depth can't, the whole
volumetric redesign is questionable and we stop before spending on SAM 2 / Depth Anything
V2 / iOS capture.

## Isolation strategy
- Use **Nutrition5k ground-truth depth** (16-bit, 10,000 units = 1 m; capped ~0.4 m).
  This isolates the *volume geometry* from the *depth model* — the depth model's error is
  measured separately in Phase 1 (Depth Anything V2 vs GT depth).
- Use a **depth-threshold food mask** (pixels above the estimated table/plate plane), not
  SAM 2 — again to isolate geometry from segmentation for now.
- Exact N5k intrinsics are unpublished. We use RealSense-D435 intrinsics at the actual
  capture resolution as a physical prior, then fit **one global scale constant** on a
  calibration split. The unknown fx·fy scale collapses into that constant, so absolute
  intrinsics are not load-bearing for the go/no-go.

## Metrics (in priority order)
1. **R²(GT mass, integrated depth-volume)** across dishes — the core signal. How much of
   the mass variance does raw geometry explain? Scale-invariant, calibration-free.
2. **Volume→grams MAPE** after a 1-parameter global scale calibration (train/test split).
   Decoupled from density and USDA — pure geometry→mass.
3. (Secondary) end-to-end **calorie MAPE** using a small density table + USDA, for
   comparison to the V1 pipeline.

## Baselines & targets
| Reference | grams/mass MAPE | calorie MAPE | notes |
|---|---|---|---|
| **V1 (Claude/LLM estimate + USDA)** | ~23–31% | ~37–43% | current shipping approach, N5k floor |
| N5k paper — mass regression, no volume | 18.7% | — | trained |
| **N5k paper — volume-assisted mass** | **13.7%** | 16.5% (end-to-end) | trained; our aspirational ceiling |
| Literature — monocular food volume | — | 16–31% | varies |

**Go / No-Go for the volumetric redesign (GT-depth upper bound):**
- ✅ **GO** if R² ≥ 0.6 **and** volume→grams MAPE ≤ 20% (beats the V1 LLM estimate).
- 🌟 **STRONG** if grams MAPE ≤ 15% (competitive with trained volume-assisted mass).
- ❌ **RECONSIDER** if GT-depth geometry can't beat V1's ~23% — a real depth model will
  only be worse, so the approach wouldn't pay off. Revisit assumptions before Phase 1.

## What this does NOT test yet (later phases)
- Depth-model error (Depth Anything V2 vs GT) — Phase 1.
- SAM 2 segmentation error — Phase 1.
- The ARKit metric path (true scale from camera pose) — Phase 3+.
- Ingredient-ratio split + density-DB accuracy — measured as they're built.
- Multi-view synthetic test set (angled/side reprojections) — built in Phase 0 as the
  scaffold for testing the default monocular path, but the volume number above uses the
  real overhead depth.
