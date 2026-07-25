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

Keep generated eval data out of the mirror (`.git-snap/info/exclude` lists
`eval/n5k_cache/`, `eval/golden.n5k.jsonl`, `eval/images/n5k_*.png`,
`eval/reports/`).

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
Model defaults to `claude-sonnet-5`; override with `RIVA_SCAN_MODEL`.

## Current production state

Prod runs the **Claude-only** scanner and, as of 2026-07-25, the **to-do CRUD**
API (`/v1/todos`, mirror commit `4392445`). Verify what is actually live rather
than trusting this file:

```bash
curl -s https://riva-snap.onrender.com/healthz
# expect: {"provider":"anthropic","model":"claude-sonnet-5",...}
```

The V2 / CalorieMama work and the volumetric pipeline remain local and
deliberately unshipped — the mirror carries only what production needs.
