# Riva governance kit (Claude Code)

Adapted from the "SWE AI kit" for Riva's `ios/` + `backend/` layout, `uv`/Supabase
tooling, and Claude-only vision. Read `CLAUDE.md` (repo root) for the rules.

## Activate
Open Claude Code in the repo root, then:
```
/hooks     # should list SessionStart, UserPromptSubmit, PreToolUse(Bash/Edit), Stop, ...
/doctor    # config sanity
```
The subagents load automatically from `.claude/agents/` — the interactive `/agents`
wizard was removed from Claude Code, so manage them by editing those files (or ask
Claude). The six agents are: planner, impact-analyzer, implementer, test-writer,
verifier, doc-writer.

## Everyday use
```
/feature <desc>   # planner → impact-analyzer → implementer → test-writer → verifier → doc-writer; stops without committing
/verify           # run the verifier on the current git diff
/pr               # produce commit message + PR body as TEXT (git/gh stay blocked)
/graph            # regenerate vault/ArchitectureGraph.md from backend/app + ios
/design <what>    # compose UI from vault/Components.md + DesignSystem.md
```

## What the guards enforce (hard blocks)
- `git push|commit|merge|rebase`, `gh pr create|merge` — gated; ask a human.
- DB access only to the sandbox `localhost:5433` — prod/staging refs blocked.
- Shell-wrapper indirection (`| sh`, `eval`, `base64 -d`, `curl | sh`, backgrounding).
- Reading `.env` / `.ssh` / `.aws` / credentials; recursive `rm` outside the working set.
- Editing `vault/{Architecture,Security,API,DesignSystem}.md`, `CLAUDE.md`, `.claude/settings.json`.
- Prompts asking to skip tests/verification or push to prod.

Note: the guard blocks trailing `&`, so background a dev server in a separate terminal
(e.g. run `uvicorn` in its own shell) rather than with `... &`.

## Local sandbox DB
```
docker compose up -d sandbox-db            # postgres:16 at localhost:5433, seeded from supabase/migrations
cd backend && .venv/bin/python -m pytest   # unit tests always; integration tests hit the sandbox, else skip
```

## The verifier gate is ADVISORY
`stop-gate.py` reminds but does not block (Riva has no full test suite yet). To make it
mandatory once tests are comprehensive, change its `sys.exit(0)` to `sys.exit(2)`.

## Changing a guard
Don't weaken a guard inline. Edit the pattern in `.claude/hooks/guard-*.py`, and record
the change in `vault/DecisionLog.md`.
