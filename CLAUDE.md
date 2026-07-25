# Project Instructions — Riva

You are operating inside a governed engineering system, not as a freeform assistant.
Read this file fully. Several rules here are also enforced by hooks (`.claude/hooks/`) —
violating those causes a hard tool block, not a warning.

Riva is a GLP-1 companion app by **The Peptide Company**: a **SwiftUI iOS app** (`ios/`)
and a **FastAPI food-scanning backend** ("Riva Snap", `backend/`, code under `backend/app/`).
Deep reference lives in the **Vault** (`vault/`) and `docs/riva-snap-context.md`.

## 1. Before anything

- Read `vault/Architecture.md` and the Vault files relevant to the request. A
  `UserPromptSubmit` hook auto-injects the routed Vault files — **do not re-read those**.
- Never read the whole repo. Load only: relevant Vault files, the relevant modules,
  DecisionLog, and recent changes.

## 2. Plan before coding

No implementation begins until a plan exists. Use the `planner` subagent for non-trivial
work. The plan states: goal, affected modules, files to modify, dependencies, risks,
testing strategy.

**Ambiguity is resolved by asking, never by inferring.** If the target module, database,
or expected behaviour is unclear — stop and ask.

## 3. Coding rules

- Prefer < 500 lines per file. Hard limit 1000 (enforced by `guard-edit.py`) — split it.
- Modular, reusable, readable, testable. No duplicated logic, no dead code.
- **Do not alter existing working code unless explicitly told to.** Refactors are a
  separate, explicitly-requested task.
- Match the surrounding code's style, naming, and comment density.
- Backend: structured logging at module boundaries (no bare `print`); fail soft (a bad
  image / USDA outage / rejected schema degrades to a clear error, never a silently wrong log).
- Before writing a SwiftUI component, check `vault/Components.md`. Reuse or extend an
  existing one; do not write a one-off. New shared components get proposed for the catalogue.

## 4. Delegation

| Need | Use |
|---|---|
| Procedural knowledge | Skill (`.claude/skills/`) |
| Isolated or parallel work | Subagent (`.claude/agents/`) |
| A rule that must not be broken | Hook (`.claude/hooks/`) |

Delegate research, test writing, and verification to subagents to keep exploration out of
the main context. `/feature <desc>` runs the full pipeline:
`planner → impact-analyzer → implementer → test-writer → verifier → doc-writer` and stops
**without committing**.

## 5. Model tiering

Planning and verification use the strongest model; implementation uses a smaller one — the
plan is already complete, so implementation is transcription. If a small model cannot
implement the plan, the plan was underspecified. Fix the plan, do not escalate the model.

## 6. Gated operations — require explicit human instruction, every time

- `git push`, `git commit`, `git merge`, opening a PR (blocked by `guard-bash.py` + deny rules)
- **Deploying**: production ships from the **separate mirror repo** (`backend/.git-snap` →
  `Riva-Snap`), and Render **auto-deploy is OFF**. Push the mirror, then Manual Deploy.
  Never do this without explicit instruction.
- Any database write outside the local sandbox; migrations against anything but the sandbox
- Adding dependencies (`uv add` / `pip install` — ask first)
- Deleting files outside the current working set

You run in auto-accept-edits mode; the deny rules in `settings.json` are approximate. Do
not route around a gate — request approval explicitly.

## 7. Data & environment

- **Production DB is Supabase** (remote Postgres, RLS). There is **no production connection
  string in this environment** by design. Server-authoritative writes go through the
  `log_scan` / `log_*` RPCs with the service-role key; clients only authenticate.
- **Local sandbox DB**: a Postgres container at **`localhost:5433`** (`docker-compose.yml`),
  seeded from `backend/supabase/migrations/*.sql`. Integration tests target this only —
  `guard-bash.py` blocks any `psql`/DB access that is not `localhost:5433`.
- **Python**: `uv` + `backend/.venv` (Python 3.12). **Not `pip`.** `requests` is not
  installed — use `httpx` / stdlib `urllib`.
- **Vision provider is Claude only**: Anthropic Messages API, default `claude-sonnet-5`
  (override `RIVA_SCAN_MODEL`). See `vault/Services.md`.
- **Secrets** live in `backend/.env` (gitignored) + Render env. Never in code or chat;
  rotate anything that leaks. `.env` reads are blocked.

## 8. Definition of done

Implementation → backend `ruff` clean + `pytest` green (`backend/tests/`, against the
sandbox DB) → `verifier` subagent reviews the diff and records a confidence score. The
`Stop` hook is **advisory** (it reminds, it does not block) until a full test suite exists.
For iOS, build via `xcodebuild` per `docs/riva-snap-context.md`.
