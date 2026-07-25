# Services

External providers and integrations. Current state.

## Anthropic Claude (vision)

- **Role:** the food/water identifier in `POST /v1/scan`. Named foods + rough
  portions only — nutrition is grounded downstream (USDA), and portion/volume
  is deterministic code, so a perception-tier model suffices.
- **Integration:** `app/vision.py`, native Anthropic **Messages API** via the
  `anthropic` SDK. Structured outputs (`output_config.format = json_schema`)
  bind the response to `SCAN_SCHEMA`; a prompt-schema fallback path exists for
  models/SDKs that reject structured outputs.
- **Model:** default `claude-sonnet-5` (`DEFAULT_MODEL`); override via
  `RIVA_SCAN_MODEL` (e.g. `claude-opus-4-8` for quality). Thinking disabled
  (perception task); Haiku predates the option and runs without it.
- **Key:** `ANTHROPIC_API_KEY`. `SCAN_SCHEMA`'s `type:[X,"null"]` unions are
  auto-rewritten to `anyOf` (`_nullable_to_anyof`) — one schema source.
- OpenAI and Groq code paths were **removed**; Claude is the only provider.

## USDA FoodData Central (grounding)

- **Role:** authoritative per-100g nutrients. For each solid item, search FDC,
  score candidates, and on a match recompute nutrients = per-100g × grams.
- **Integration:** `app/fdc.py` (`search_foods`, pooled `httpx.Client`,
  `foods/search`) + `app/grounding.py` (`best_match`, `match_score`,
  `grounded_nutrients`).
- **Scoring:** token coverage (threshold 0.6) + first-token/category bonus −
  wrong-form penalty (flour/dry/powder/mix/etc., but not "raw"). Data-type
  preference: Foundation → SR Legacy → Survey (FNDDS).
- **Key:** `FDC_API_KEY` (defaults to `DEMO_KEY` if unset).
- **Known bug:** FDC search returns HTTP 400 on **parenthetical queries**
  (e.g. `"Roasted sweet potato (with oil)"`). Grounding is best-effort, so this
  silently drops the match rather than failing the scan. Fix is an open TODO.

## CalorieMama (v2, local/uncommitted)

- **Role:** fast single-dish **namer** for real phone photos. Nutrition is
  unreliable and NOT portion-aware (fixed per food type — e.g. "Momo" → 1667
  kcal / 0g everything), so it is an **identifier only**, useless for macros.
- **Endpoint:** `https://caloriemama.ai/api/food_recognition_proxy`. **No API
  key** — it gates on `Referer: https://caloriemama.ai/` and
  `Origin: https://caloriemama.ai` (it powers CalorieMama's own web demo).
- **Why the proxy:** the endpoint sends no `Access-Control-Allow-Origin`, so a
  browser is CORS-blocked from reading the response. `POST /v2/scan` in
  `app/main.py` does the server→server call (no CORS), resizing to 544×544 JPEG
  and adding the Referer/Origin headers.
- **Response:** `results[].items[]` with `name`, `score` (a relevance RANK, can
  exceed 100 — not a probability), `nutrition`, `servingSizes`.
- **Best-of-both target:** CalorieMama name → USDA grounding for real macros.
