# Real-world volumetric eval — capture protocol + harness

Why this exists: Phase-0 showed single-view depth can't recover volume, and
**Nutrition5k is top-down-only so it cannot test the multi-view redesign**
(`../volumetric/FINDINGS.md`). This is the fair test — real phone captures of real
plates with **kitchen-scale ground-truth grams**. Today it scores the current V1
LLM scanner as the baseline; the volumetric pipeline will be scored the same way.

## What to capture (per dish) — takes ~1 minute

1. **Weigh the plated food** on a kitchen scale → `grams_total`. Ideally weigh each
   component before plating → `components` (this is the gold standard for scoring).
2. **Note** the dish name, ingredients, and any *hidden* ingredients (oil, butter,
   cream) — these are the "invisible ingredients" the hint is meant to capture.
3. **Put a scale reference in frame**: a credit card (85.6 mm long) or a coin, OR use
   a known container (note its diameter). Needed for the default (non-ARKit) scale.
4. **Record a 3–5 s arc video**: hold the phone over the dish, start at a ~45° side
   angle and sweep smoothly up to top-down. Keep the dish centered. Any camera app is
   fine for now (the ARKit depth+pose capture comes with the iOS build).
5. Save it as `capture.mp4`.

Aim for **20–30 dishes** spanning: light vs heavy portions, flat vs piled, single-item
vs mixed bowls, and a few cuisines. Include some deceptively-dense plates (rice mounds)
— those are where 2D scanners fail.

## Where to put it

```
dataset/<dish_id>/
    capture.mp4        # your arc clip  (or a frames/ dir of stills)
    truth.json         # required — see schema below
    arkit_poses.json   # optional — per-frame pose+intrinsics (ARKit build, later)
```

`truth.json` (minimum = the 3 required fields):
```json
{
  "dish_id": "d001",
  "name": "chipotle chicken bowl",
  "grams_total": 540,
  "components": [
    {"name": "brown rice", "grams": 180},
    {"name": "grilled chicken", "grams": 150},
    {"name": "black beans", "grams": 90},
    {"name": "guacamole", "grams": 120}
  ],
  "kcal_total": 640,
  "container": {"type": "bowl", "diameter_cm": 20.3},
  "scale_reference": {"type": "credit_card", "long_mm": 85.6},
  "hint": "chipotle chicken bowl, cooked in olive oil",
  "device": "iphone15pro",
  "arkit": false
}
```
Only `dish_id` (must match the folder), `name`, and `grams_total` are required.
`kcal_total` enables calorie scoring; `components`/`ingredients` enable recall.

## Run it

```bash
cd backend/eval/realworld
../../.venv/bin/python ingest.py                 # validate + extract frames from videos
../../.venv/bin/python run_realworld_eval.py     # score the V1 baseline; writes reports/
```

`ingest.py` validates every dish and extracts the sharpest 6 frames from each clip
(the server-side twin of the on-device Step-3 blur filter, `frames.py`). The runner
scores whichever predictor you pick (`--predictor v1_llm` today) with the same metrics
as the volumetric METRICS.md: grams MAPE, R²(grams), calorie MAPE, ingredient recall.

`dataset/example_n5k_chicken/` is a template fixture (built from one N5k image) so the
harness runs before you've captured anything — delete it once you have real dishes.
