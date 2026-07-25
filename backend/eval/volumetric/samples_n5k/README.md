# Nutrition5k labeled samples

15 held-out Nutrition5k dishes with ground-truth labels — a portable, labeled set for
the SAM 2 / volume prototyping notebook (`../multiview/colab/sam2_prototype.ipynb`) and
the volume eval. Assembled from the golden set + downloaded overhead captures.

## Contents
- `<dish_id>.png` — RGB, overhead top-down (the N5k realsense_overhead camera).
- `<dish_id>_depth.png` — 16-bit **ground-truth depth**, `10000 units = 1 metre`
  (capped ~0.4 m). Optional; enables the metric-volume check without a depth model.
- `labels.jsonl` — one JSON object per dish:
  `image, depth, dish_id, dish, ingredients[], grams_total, kcal, protein_g, carb_g,
  fat_g, view, source`. Masses in grams, energy in kcal, macros in grams.

## Caveats
- **Single view per dish** (top-down only) — N5k can't test multi-view volume; use it for
  segmentation/ID/metric-sanity, not to validate the multi-view gain. See
  `../FINDINGS.md` and `../../realworld/` (the real weighed-mass multi-view test).
- N5k images are lab-rig captures (domain gap vs phone photos) → a pessimistic floor.

## Use
- Notebook: upload a few `<dish_id>.png` (and use `labels.jsonl` for the truth grams/kcal).
- Metric: `../run_volumetric_eval.py` already scores the volume engine on this set via GT depth.

This folder is **git-ignored** (derived N5k data + redistribution terms) — regenerate from
the downloaded eval set anytime.
