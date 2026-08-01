# Deployment

How Riva Snap ships to production. Current state — READ BEFORE DEPLOYING.

## The mirror-repo model (the thing that bites you)

Production does **not** deploy from the working repo. There are two GitHub
repos:

- `Riva-App` — the monorepo (`ios/` + `backend/`), `origin` of the working
  tree. **Pushing here does NOT deploy anything.**
- `Riva-Snap` — the **deploy mirror** Render watches; backend content sits at
  its repo root. Its git metadata lives at **`backend/.git-snap`** (a separate
  git dir whose work-tree is `backend/`, gitignored).

To ship a backend change, push the mirror (only with explicit permission):

```bash
cd backend
GD="$PWD/.git-snap"; WT="$PWD"
git --git-dir="$GD" --work-tree="$WT" add <specific files>
git --git-dir="$GD" --work-tree="$WT" commit -m "..."
git --git-dir="$GD" --work-tree="$WT" push origin main
```

Stage **specific files**, never `add -A`: the work-tree is the whole of
`backend/`, so a blanket add would sweep in tests and local-only pipelines.
`.git-snap/info/exclude` is the backstop and lists the generated eval data
(`eval/n5k_cache/`, `eval/golden.n5k.jsonl`, `eval/images/n5k_*.png`,
`eval/reports/`) plus everything else the mirror omits by design — `tests/`,
`pytest.ini`, `ruff.toml`, `requirements-dev.txt`, `app/volumetric/`,
`scripts/`, `serving/`.

### Rebuilding `.git-snap` when it is missing

It is gitignored local-only state, so a fresh clone of `Riva-App` does not have
it and the push command above fails with `fatal: not a git repository`. It is
disposable — rebuild it from GitHub rather than hunting for it:

```bash
git clone --no-checkout https://github.com/ashutoshanandmehta/Riva-Snap.git /tmp/riva-snap-clone
mv /tmp/riva-snap-clone/.git /Users/khedar/Riva-App/backend/.git-snap
cd backend
GD="$PWD/.git-snap"; WT="$PWD"
git --git-dir="$GD" --work-tree="$WT" read-tree HEAD   # seed the index, write no files
git --git-dir="$GD" --work-tree="$WT" status --short   # now shows the real drift
```

`read-tree` is the important part: without it the index is empty and every file
reads as untracked. **Never run `checkout`, `reset --hard`, `stash` or `clean`
against this git dir** — its work-tree is the live `backend/` directory and
those commands would overwrite your working copy.

Before pushing, confirm the commit stands on its own — `main.py` imports its
siblings unconditionally, so a runtime file left out of the mirror is a boot
failure, not a missing feature:

```bash
mkdir -p /tmp/deploycheck && git --git-dir="$GD" archive HEAD | tar -x -C /tmp/deploycheck
cd /tmp/deploycheck && PYTHONPATH=. python -c "from app.main import app"
```

## Render

- Service **`riva-snap`**, live at **https://riva-snap.onrender.com**,
  Blueprint-managed by `backend/render.yaml`.
- **Auto-deploy is OFF.** After pushing the mirror: **Manual Deploy → Deploy
  latest commit**. Nothing ships until you click it.
- **Free tier:** CPU-only, 512 MB RAM, spins down on inactivity. A **5-minute
  cron** keeps it warm to avoid cold starts.
- Build: `pip install -r requirements.txt`; start:
  `uvicorn app.main:app --host 0.0.0.0 --port $PORT`; health check `/healthz`.
- `PYTHON_VERSION` 3.12.6. `RIVA_SCAN_DEBUG=true` during tuning.

## Env vars (render.yaml, `sync: false` secrets)

`ANTHROPIC_API_KEY`, `FDC_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY` (Render prompts for these on blueprint deploy).
Model defaults to `claude-sonnet-5`; override with `RIVA_SCAN_MODEL`,
`RIVA_SUGGEST_MODEL`, `RIVA_CHAT_MODEL` or `RIVA_FOOD_SEARCH_MODEL` — all
default to empty, meaning the Sonnet default, so none needs setting.

Prod has an `FDC_API_KEY`; the local `backend/.env` does **not**. USDA answers
403 to an empty key, so a local run of anything that grounds — the scanner or
food search — silently exercises only the fail-soft path and returns
`matched: false` for everything. `/healthz` reports `fdc_key_present`, so check
it before concluding a grounding change did not work.

## Current production state

Mirror `main` is at **`4198853`** — "Add food search: USDA-priced replacements
for a mis-detected item", deployed 2026-08-01 (monorepo `e240652`). Prod runs
the **Claude-only** pipeline (the earlier OpenAI `gpt-5.2` note is obsolete),
serves all four `/v1/chat*` routes plus `streak_days` on `/v1/dashboard`, and
now `POST /v1/food-search` behind the scan editor. **32 documented paths** in
`/openapi.json`.

```bash
curl -s https://riva-snap.onrender.com/healthz
# {"provider":"anthropic","model":"claude-sonnet-5",...}
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
     https://riva-snap.onrender.com/v1/chat -d '{"query":"hi"}'
# 401 — the auth gate. A 405 means the router is NOT deployed: the static
# "/" mount is answering an unrouted POST. Same test for /v1/food-search.
curl -s https://riva-snap.onrender.com/openapi.json | python3 -c \
  "import sys,json;print(sorted(json.load(sys.stdin)['paths']))"
# the honest answer to 'what is actually live' — no auth needed
```

The route count is the fastest way to tell a deploy landed. Auto-deploy is off,
so a pushed mirror commit and a *running* one are different facts: check, do
not assume.

Deliberately **not** in the mirror, and local-only by choice: `app/volumetric/`
(the debug ARKit pipeline — `main.py` guards its import, so its absence just
logs a warning), the eval harness extras, and `tests/` with `pytest.ini` /
`ruff.toml` / `requirements-dev.txt`. Tests live in `Riva-App`; the mirror
carries runtime code only.

The V2 / CalorieMama endpoint (`POST /v2/scan`) **is** live in prod.
