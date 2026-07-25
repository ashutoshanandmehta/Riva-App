# Architecture

_CANONICAL — authoritative architecture summary for Riva Snap. Current state._

Riva is a GLP-1 companion app by The Peptide Company. Two parts:

- **iOS app** (SwiftUI, `ios/`, bundle id `in.riva`) — the product. Tabs: Home, Wellness, Snap, Medication, Tracker.
- **Backend** ("Riva Snap", `backend/app/`) — a FastAPI service whose centerpiece is the food/water photo scanner, plus logging APIs for weight, shots, protein/nutrition, side effects, and check-ins.

## Scan pipeline (stateless)

The scan itself stores nothing. One `POST /v1/scan` runs four stages:

1. **Preprocess** (`preprocess.py`) — fix EXIF rotation, downscale to ~1024px, re-encode JPEG q85. Keeps each scan cheap and fast.
2. **Vision** (`vision.py`) — one Claude call. **Anthropic native Messages API**, default model `claude-sonnet-5` (override `RIVA_SCAN_MODEL`), with **structured outputs** (`SCAN_SCHEMA`). The VLM is an **identifier only**: it names foods and gives rough portions; nutrition numbers it emits are a fallback. Thinking disabled (perception task). OpenAI/Groq paths were removed — Claude only.
3. **USDA grounding** (`grounding.py` + `fdc.py`) — for each solid item, search USDA FoodData Central, score candidates, and on a match recompute nutrients from lab per-100g values × estimated grams (the MATCHED badge). Portion/volume is deterministic downstream code, not the LLM. Lookups run in parallel (ThreadPoolExecutor). Best-effort: an FDC outage degrades to model estimates.
4. **Assemble** (`main.py` `_assemble`) — round to DB units, sum totals, compute `nutrition_day_delta`, set `mode_mismatch`. Only plain water fills `water_ounces`; a latte is calories, not hydration.

The scan response's `nutrition_day_delta` matches the `nutrition_days` table exactly (integer calories/protein/carb/fiber + water ounces), so persistence is a pass-through, not a translation.

## Persistence (Supabase)

Writes are **server-authoritative**. Clients only authenticate; they have no direct write path. `POST /v1/log` verifies the user's Supabase token, then calls the `log_scan()` Postgres function with the **service role key**. That function computes the user's local calendar day from their profile timezone, inserts a `food_entries` history row, and upserts the day's `nutrition_days` totals in one transaction. Row Level Security isolates every user's data. When Supabase env vars are absent, the service runs in open stateless mode (scans work, logging 503s) — useful for local dev and the eval harness.

Identity today: a silent per-device account provisioned via `POST /v1/device/session` (iOS); the web tester uses email-code sign-in.

## Module map (backend/app/)

- `config.py` — pydantic-settings from env/`.env`; keys whitespace-stripped.
- `main.py` — FastAPI routes, scan assembly, mode-mismatch logic, static web mount at `/`.
- `preprocess.py` — image normalization.
- `vision.py` — Anthropic client factory, model resolution, `SCAN_SCHEMA`, nullable→anyOf schema rewrite, JSON parse.
- `grounding.py` — match scoring (token coverage + first-token bonus − wrong-form penalty), per-100g scaling.
- `fdc.py` — pooled USDA FDC HTTP client, nutrient-id mapping.
- `backend.py` — Supabase token verification + all service-role RPC/REST writes and reads.
- `schemas.py` — DB-aligned Pydantic request/response models.
- `prompts/scan_v1.md` — versioned prompt (echoed in every response).

## External dependencies

- **Anthropic Claude** — vision (`ANTHROPIC_API_KEY`).
- **USDA FoodData Central** — nutrient grounding (`FDC_API_KEY`).
- **Supabase** — Auth + Postgres (`SUPABASE_URL/ANON_KEY/SERVICE_ROLE_KEY`).
- **CalorieMama** — proxied by the local/uncommitted `POST /v2/scan` (identifier only).

## Design principles

- Stateless pipeline, DB-shaped response contract.
- Grounded numbers beat clever numbers: LLM identifies, USDA prices.
- Fail soft: outages/bad schema/unreadable image degrade to a usable answer, never a silently wrong log.
- Everything observable: per-stage latency, per-candidate match scores, raw output behind a debug flag.

See `ArchitectureGraph.md` for the dependency diagram. Regenerate with /graph.
