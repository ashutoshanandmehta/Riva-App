# Multi-item / multi-view volumetric flow

Extends the tap-and-hold volumetric flow to (a) meals with multiple items and
(b) N views per capture, with a scale-reference prior and a required plausibility
gate. This is the classical/uncalibrated prototype; SAM 2, monocular/ARKit depth,
and calibrated space-carving slot in behind the interfaces noted below.

## Current-state assessment (what existed before this)
- **V1 scanner** (`app/vision.py`): multi-item at the *identification* level
  (`SCAN_SCHEMA.items[]`) with per-item LLM gram guesses + USDA — but **no volume**.
- **Phase-0 volume engine** (`../volume_engine.py`): single largest connected
  component (`_food_mound`) — **one item, one blob, one frame**.
- **Redesign doc v2**: measures **one total volume**, then splits it by LLM-guessed
  ratios (Step 6) — i.e. *not* per-item volume. This is the `§11` gap.
- **Multi-view**: nothing consumed N views; Phase-0 is single-frame.
- Phase-0 already showed single-view depth is too weak (R²=0.16) → multi-view is
  the point, not polish.

## Design (as implemented)
- **View discovery** (`capture_set.py`): a capture set = all images in a directory,
  sorted, N ≥ 1. No hardcoded names or view count.
- **Segmentation** (`geometry.segment_food`): GrabCut seeded by a centre rectangle —
  a stand-in for **SAM 2 seeded by the tap anchor**. Returns the food footprint mask.
- **View role** (`geometry.infer_role`): heuristic top / side / oblique from mask
  geometry — a stand-in for **ARKit camera pose**. (Imperfect; pose replaces it.)
- **Per-view volume** (`geometry.view_volume`): parametric. Top view → footprint ×
  class-prior height; side/oblique → cylinder from width × visible height. Metric
  scale is **seeded from the food-class footprint prior** (see below).
- **Fusion — chosen: per-view estimate + confidence-weighted geometric mean**
  (`geometry.fuse`). Complementary roles reinforce (footprint from top, height from
  side). **Degrades to N=1** with a confidence penalty.
  - *Rejected: silhouette intersection / space carving* — needs calibrated per-view
    poses we don't have on uncalibrated phone photos. It's the **upgrade for the
    ARKit era** (calibrated visual hull), and plugs in behind `fuse`.
- **Scale reference = prior only** (`scale_priors.json`, `food_classes.json`): metric
  scale is seeded from published dimensions (plate/vessel/food-class sizes) and
  **refined per detected food class** — never treated as ground truth. In-frame
  reference detection (plate/fork/card) is a documented refinement hook that would
  raise confidence when present.
- **Plausibility gate — REQUIRED** (`plausibility.py`): volume → mass → kcal via the
  per-class density + kcal/100g, then validate volume against the class's
  `volume_ml [min,max]`:
  - in range → **log**; mildly out → **clamp** to bound + low confidence;
    grossly out (>3× beyond) → **retake** (not logged). Never logs the raw value.
  - Ranges live in `food_classes.json` (per class: `volume_ml`, `density_g_ml`,
    `kcal_100g`, `footprint_cm`, `height_cm`); unknown classes fall back to `_generic`.

## Multi-item + segmentation (SAM 2 seam — built)
`segmenter.py` is pluggable:
- **ClassicalSegmenter** (GrabCut, default, no deps/cost) — one food mask per view →
  single item across views.
- **Sam2ReplicateSegmenter** — SAM 2 automatic mask generation on Replicate returns a
  mask **per item**; masks are filtered to food-item-sized regions, associated across
  views (`associate.py`, centroid/area heuristic), and each item is volumed
  independently through the same `view_volume`/`fuse`/`gate` path. **This closes the
  `§11` gap** (the doc split one total volume by LLM ratios; we now measure each item).

Selection is automatic: SAM 2 when `REPLICATE_API_TOKEN` is set (model override
`RIVA_SAM2_MODEL`, default `meta/sam-2`), else classical. Force with
`--segmenter classical|sam2`. The exact Replicate field names are centralised in
`segmenter.py` and should be confirmed on first live run.

`LogMeal` (logmeal.com/api) is a **reference** for the multi-item detection/
classification step (its screenshot demo) — a future integration, not a dependency.

## Run
```bash
cd backend/eval/volumetric/multiview
../../../.venv/bin/python run_multiview.py "<dir of N views>"               # Claude ID -> class
../../../.venv/bin/python run_multiview.py "<dir>" --no-llm --class burger  # offline geometry+gate
../../../.venv/bin/python run_multiview.py "<dir>" --segmenter sam2         # per-item masks (needs REPLICATE_API_TOKEN)
../../../.venv/bin/python -m pytest test_multiview.py -q                    # offline plumbing tests
```
To enable SAM 2 (hosted): add `REPLICATE_API_TOKEN=...` to `backend/.env` (and to
Render env if the volumetric endpoint ever ships). Verified end-to-end against
`meta/sam-2` (schema confirmed); currently blocked only on Replicate account credit.

## Prototype for free first (the practical split)
- **Free GPU (Colab/Kaggle):** `colab/sam2_prototype.ipynb` — tune SAM 2 (tap-prompt +
  automatic) + per-view volume + the gate on your sample data, no cost. Regenerate with
  `colab/build_notebook.py`. Its volume/gate logic mirrors `geometry.py`/`plausibility.py`,
  so tuned params port straight back.
- **Hosted (Replicate credit / Modal / RunPod):** the endpoint the backend calls, once the
  approach is validated — drops in behind the same `Segmenter` interface (`segmenter.py`),
  no pipeline changes.
Validated on `sample multi view pictures/` (one cheeseburger, 3 views): fused ~621 mL
→ ~342 g → ~854 kcal, gate "log"; single view degrades to lower confidence; the gate
clamps/retakes out-of-range volumes.

## Known limitations (honest)
- Uncalibrated RGB → volume is a rough parametric estimate; **real accuracy needs
  depth (ARKit/monocular) + SAM 2 masks + a real weighed-mass eval** (`../../realworld/`).
- View-role heuristic is unreliable (top-down burger was tagged "side"); ARKit pose fixes it.
- Multi-item per-item volume needs SAM 2 (`REPLICATE_API_TOKEN`); classical is
  single-item. The Replicate adapter + cross-view association are built and unit-tested
  offline, but not yet live-fired (no token) or validated on real multi-item captures.
