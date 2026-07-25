# Testing

Two layers: the accuracy **eval harness** and a **unit/integration test suite**.

## Eval harness (`backend/eval/`)

Runs the real scan pipeline over a golden image set and reports accuracy.

- `run_eval.py` — runs the V1 pipeline (`--golden/--images/--limit`) and
  reports **dish-name match rate**, **calorie MAPE**, **portion-gram MAPE**,
  **ingredient recall**, **scan-type accuracy**, **USDA (FDC) match rate**, and
  **latency percentiles**. Writes a markdown report to `eval/reports/`.
- `n5k_to_golden.py` — downloads Nutrition5k over plain HTTPS (bucket path is
  doubly nested), samples held-out `rgb_test` dishes, writes
  `golden.n5k.jsonl`. Golden set = **15 held-out N5k dishes**. Stdlib only.
- `eval_caloriemama.py` — CalorieMama identification eval.
- `compare_v1_v2.py` — V1 vs V2, both USDA-grounded, per-100g density.

Run via the venv, e.g. `backend/.venv/bin/python eval/run_eval.py --golden
eval/golden.n5k.jsonl`.

### N5k domain-gap caveat

Nutrition5k images are top-down lab-rig shots with depth sensors — a real
domain gap vs. actual phone photos. Every eval number is a **pessimistic
floor**. A real-phone-photo eval set is the fair test (open TODO). This is why
Haiku's poor N5k score is not by itself disqualifying, and why fine-tuning on
N5k is deferred.

### Acceptance gate (for iOS integration)

- ≥ 80% dish-name match
- ≤ 25% calorie MAPE
- ≥ 95% scan-type accuracy
- ≥ 60% USDA match rate
- p95 latency < 6s

Latest numbers (Sonnet 5, 15 N5k dishes): name 73%, ingredient recall 53%, FDC
73%, calorie MAPE 37%, portion-gram MAPE 31%, latency p50 8.4s — a pessimistic
floor per the caveat.

## Unit + integration suite (`backend/tests/`, being added)

A **pytest + ruff** suite is being added under `backend/tests/`, run through
`backend/.venv` (uv-managed; `requests` not installed — use httpx/urllib).

- **Unit tests** cover pure logic (grounding scoring, schema rewrite, assembly,
  mode-mismatch) with no external services.
- **Integration tests** target the **local Postgres sandbox at localhost:5433
  only** (loads the same `supabase/migrations` SQL) — never the remote Supabase
  DB. This exercises the `log_*` functions and RLS end to end.
- `ruff` is the linter/format check.

## Volumetric real-device validation (2026-07-24)

**V3 end-to-end validated on real iPhone 17 (tier B, ARKit poses):**
- Capture flow (6 frames): on-device capture → API identify, segment, carve, plausibility gate → log.
- Latency: total ~27s (identify 6.2s, segment 20.8s, carve, log), within the 120s client timeout.
- Segmentation performance: per-frame downscaling to 512px longest side + upscale reduces GrabCut 
  from ~35s/frame to ~572ms/frame (61x speedup). Regression tests: 3 cases in `test_volumetric_geometry.py`.
- **Accuracy status:** UNVALIDATED. Two failure modes observed:
  - Capture A: volume 242.5 ml, but visual hull hit carve grid boundary (grid too coarse for real portions).
  - Capture B: volume 45.4 ml, undersegmented / partial silhouette, clamped to plausible bound.
  - Both errors are upstream of carving: segmentation quality + grid sizing are the open tuning levers.
  - GO gate: R²≥0.6 and grams MAPE≤20% vs v1 baseline ~23% — test against weighed ARKit captures pending.
