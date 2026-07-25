# Volumetric Phase-0 — findings & recommendation

_Run 2026-07-22 on the 15-dish N5k golden set. See METRICS.md for the pre-registered targets._

## Result
| Metric | Result | Go target | V1 LLM baseline |
|---|---|---|---|
| R²(GT mass, depth-volume) | **0.16** | ≥ 0.60 | — |
| Leave-one-out grams MAPE | **~90%** | ≤ 20% | ~23% |

**Verdict: RECONSIDER the single-view path.** Even with *ground-truth* depth and food
isolated to the central mound, integrating a single overhead depth frame barely predicts
food mass — far worse than the current LLM estimate.

## Why this is a robust result, not a tuning artifact
- **R² is scale-invariant.** The headline number does not depend on the (unpublished) N5k
  intrinsics, the density constant, or the global scale calibration — all of those only
  affect slope/offset, not correlation. No amount of scale tuning fixes R²=0.16.
- We tested the *best case*: real depth (not an estimated depth model), and the food mound
  isolated by connected component. A real deployment is only harder.
- The failure is geometric, not arithmetic. The volume integral is trivial once you have
  (food mask, plate-surface reference, metric scale). Getting those from **one top-down
  frame** is the problem: the plate-vs-food reference is ambiguous and a top-down view
  flattens pile height — literally pain-point #2 in the redesign doc.

## What this does and does not say
- ✅ **Confirms the redesign's core premise:** a single 2D/top-down capture is insufficient
  for volume. The multi-view arc and the ARKit metric path are *justified*.
- ❌ **Does NOT validate the multi-view redesign** — and N5k *cannot*, because it is
  top-down-only. A synthetic multi-view generator built from single-view N5k RGB-D adds no
  real parallax, so it can test pipeline *mechanics* but not *accuracy gains*.
- 🔎 **Segmentation is load-bearing.** Depth-threshold masks still over-include the plate
  (volumes ~5× inflated, density slope 0.12 vs food's ~0.6–1.0 g/mL). SAM 2-quality masks
  are a hard requirement, not a nicety.

## Recommendation — revised build order
1. **The ARKit metric multi-view path is likely REQUIRED, not a "preferred vs fallback".**
   The monocular single-view default path looks too weak to ship on its own.
2. **Build a real eval set before the GPU tier:** phone arc-videos of dishes with
   ground-truth mass (kitchen scale) + a scale reference, ideally on ARKit devices. This is
   the only fair test of the redesign, and N5k can't substitute for it.
3. **Defer** standing up the Replicate GPU monocular tier (SAM 2 + Depth Anything V2) until
   we know the monocular path is worth it — prove the ARKit metric path on a small weighed
   set first.

De-risk win: we learned this from ~150 lines of numpy and 15 free depth maps, before
spending on GPU inference, orchestration, and the full iOS capture build.
