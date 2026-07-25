# Database

Supabase (remote Postgres) with Row Level Security. Schema from
`backend/supabase/migrations/0001_nutrition.sql` and `0002_logging.sql`.

## Tables

**0001 — nutrition core**
- `profiles` — one row per `auth.users` id. name, date_of_birth, gender,
  clinician_name, start_weight, goal_weight, height_inches, **timezone**
  (default `America/New_York`).
- `health_goals` — six boolean program flags: glp1_support, weight_mgmt,
  nutrition_diet, muscle_preserve, exercise_move, sleep_recovery.
- `nutrition_goals` — protein_goal, carb_goal, fiber_goal, water_goal (int).
- `nutrition_days` — daily aggregate: calories, protein_grams, carb_grams,
  fiber_grams, water_ounces. Unique on `(user_id, day)` where not deleted.
- `food_entries` — one row per accepted scan: scan_type, items (jsonb),
  the same nutrient columns, source, model, prompt_version.

**0002 — logging**
- `medication_plans` — name, current_dose_mg, cadence_days, dose_frequency,
  start_date, is_active. Unique active plan per user.
- `shots` — medication_name, dose_mg, taken_at, injection_site (6-value CHECK),
  comfort_rating (1–5), plan_id.
- `weights` — pounds, dose_mg snapshot, measured_at.
- `side_effect_logs` + `side_effect_log_items` — daily log (unique per user/
  date) with per-effect severity (9 allowed effects, severity 1–5).
- `checkins` + `checkin_answers`, plus global config `checkin_questions` /
  `checkin_options` (seeded: mood, energy, sleep, nausea, appetite; value 5 =
  best). Unique check-in per user/date.

Most tables carry `deleted_at` (soft delete), `created_at`/`updated_at`, and a
`set_updated_at()` trigger. A `handle_new_user()` trigger auto-provisions
`profiles`, `nutrition_goals`, and `health_goals` on signup.

## Server-authoritative write path

Clients never write directly. RLS grants authenticated users **SELECT only**
(scoped to `user_id = auth.uid()`); there are no authenticated INSERT/UPDATE
policies on the logged tables. All writes go through `SECURITY DEFINER`
Postgres functions called with the **service role key** from `app/backend.py`:

- `log_scan()` — inserts a `food_entries` row and upserts the day's
  `nutrition_days` totals in one transaction; returns the updated day totals.
- `log_shot()` — inserts a shot and syncs the active plan's `current_dose_mg`
  (creates a plan if none).
- `log_weight()` — inserts a weight with a dose snapshot from the active plan.
- `log_side_effects()` — replaces the day's effect set.
- `log_checkin()` — upserts one answer for today's check-in.

Each is `REVOKE`d from PUBLIC/anon/authenticated — only the service role runs
them. The server verifies the caller's bearer token (Supabase `/auth/v1/user`)
before calling, and passes the verified `user_id`.

## Timezone-based day calculation

Each `log_*` function reads the user's `profiles.timezone` and computes
`v_day := (now() AT TIME ZONE COALESCE(tz,'America/New_York'))::date`, so
"today" is the user's local calendar day, not UTC.

## Local sandbox

A local Postgres sandbox at **localhost:5433** is being added for integration
tests. It loads the **same** `supabase/migrations/*.sql`, so the schema matches
production. Integration tests target this sandbox only — never the remote
Supabase DB.
