# Security

_CANONICAL — security posture and gated operations. Current state._

## Secrets hygiene

- All credentials live in `backend/.env` (gitignored) locally and in **Render
  env vars** in production — **never** in code, commits, chat, or the mirror
  repo. Keys: `ANTHROPIC_API_KEY`, `FDC_API_KEY`, `SUPABASE_URL`,
  `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
- `config.py` whitespace-strips keys/URLs (dashboards inject line wraps that
  become illegal HTTP header values).
- The Supabase **anon key is public by design** (shipped to the web tester via
  `/v1/config`); the **service_role key is server-only** and must never reach a
  client. Rotate anything that leaks.

## Gated operations — require explicit human instruction

Do NOT perform any of these without an explicit ask from the owner:

- **git commit / push / merge** to either repo. The owner tests locally first;
  a prior push was reverted at their request.
- **Deploys** (mirror push + Render Manual Deploy — see `Deployment.md`).
- **Database writes outside the local sandbox** — never write to the remote
  Supabase DB from tooling.
- **Schema migrations** against remote Supabase.
- **Adding dependencies** (`requirements.txt` / uv).

## Server-authoritative data access

- RLS isolates every user's rows (`user_id = auth.uid()`, SELECT-only for
  authenticated). No client has a direct write path — all writes go through
  `SECURITY DEFINER` `log_*` functions run with the service role after the
  server verifies the bearer token. See `Database.md`.

## Known exposure: public anonymous `/v1/scan`

`/v1/scan` was deliberately made **anonymous** so the public web tester works
(the web page is a test tool; iOS is the product). Consequence: anyone with the
URL can trigger paid Claude + USDA calls — an **open cost surface**. Accepted
for now; rate-limiting / a cost cap is a possible follow-up. `/v1/scan` writes
nothing to the DB — persistence only happens on the authenticated `/v1/log`.

## Other notes

- CalorieMama's `/v2/scan` proxy uses Referer/Origin spoofing, not a key; it
  server-side proxies to avoid browser CORS. Local/uncommitted.
- Python tooling is uv + `backend/.venv`; `requests` is not installed — use
  `httpx` / stdlib `urllib`.
