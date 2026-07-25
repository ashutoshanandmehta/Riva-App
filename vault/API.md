# API

_CANONICAL — FastAPI endpoints from `backend/app/main.py`. Current state._

Auth model: when Supabase env vars are set, logging/account routes require a
`Authorization: Bearer <token>` header (verified via Supabase Auth). `/v1/scan`
is **anonymous by design** (public web tester). In open stateless mode (no
Supabase configured) the authenticated routes return 503.

## Scan

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/scan` | anon | Photo → dish, portion, calories, macros. Preprocess → Claude vision → USDA grounding → assemble. Stateless, no DB write. Form fields: `image`, `hint?`, `mode` (auto/food/water), `debug?`. |
| POST | `/v2/scan` | anon | **Local/uncommitted.** Proxies the image to CalorieMama recognition (identifier only). |

## Logging (bearer)

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/log` | Persist an accepted scan; returns updated day totals. |
| POST | `/v1/log/weight` | Log a body weight (20–1500 lbs). |
| POST | `/v1/log/shot` | Log a medication shot (dose, site, comfort); syncs the active plan's dose. |
| POST | `/v1/log/side-effects` | Replace today's side-effect set (+ note). |
| POST | `/v1/log/checkin` | Answer one daily check-in question (e.g. sleep). |

## Identity

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/device/session` | anon | Mint a Supabase session for a stable `device_id` (silent per-device account, no sign-in). |

## Profile, goals, plan (bearer)

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/me` | Profile + nutrition goals + health goals + active plan. |
| POST | `/v1/profile` | Update profile fields (partial). |
| POST | `/v1/goals` | Update nutrition goals (protein/carb/fiber/water, 0–2000). |
| POST | `/v1/health-goals` | Update the six onboarding program-goal flags. |
| POST | `/v1/plan` | Upsert the active medication plan (name, dose, cadence). |

## Reads & data (bearer)

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/dashboard` | One-call aggregate for Home/Medication/Tracker. |
| GET | `/v1/weights` | Weight history (`limit`, max 200). |
| GET | `/v1/shots` | Shot history (`limit`, max 200). |
| GET | `/v1/side-effects` | Daily side-effect logs (`days`, max 90). |
| GET | `/v1/export` | The user's complete data as one JSON object. |
| DELETE | `/v1/account` | Delete the auth user (rows cascade). |

## Public / meta

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/healthz` | anon | Status + `provider:"anthropic"`, resolved `model`, `prompt_version`, key-present flags. |
| GET | `/v1/config` | anon | Client bootstrap (backend_enabled, public Supabase URL + anon key). |
| GET | `/` | anon | Static web tester (`backend/web/`, mounted). |

Notes: `mode` never forces interpretation — the server sets `mode_mismatch`
when detected content disagrees with the chosen mode. `/v1/log` accepts only
`scan_type` in food/beverage/water.
