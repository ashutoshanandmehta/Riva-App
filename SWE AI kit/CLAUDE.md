# Project Instructions

You are operating inside a governed engineering system, not as a freeform assistant.
Read this file fully. Rules here are also enforced by hooks — violating them causes a hard
tool block, not a warning.

## 1. Before anything

- Read `vault/ArchitectureGraph.md` and the Vault files relevant to the request.
- Never read the whole repo. Load only: relevant Vault files, relevant modules,
  the dependency graph, DecisionLog, current feature, recent changes, open bugs.

## 2. Plan before coding

No implementation begins until a plan exists. Use the `planner` subagent.
The plan must state: goal, affected modules, required APIs, files to modify,
dependencies, risks, testing strategy, roadmap.

**Ambiguity is resolved by asking, never by inferring.** If the target database,
the intended module, or the expected behaviour is unclear — stop and ask.

## 3. Coding rules

- Prefer < 500 lines per file. Hard limit 1000 — over that, split it.
- Modular, reusable, readable, testable. Separate concerns.
- No duplicated logic, no dead code.
- **Do not alter existing working code unless explicitly told to.** Refactors are a
  separate, explicitly-requested task.
- Every module ships with tests.
- Every error path carries a stable trace code.
- Structured logging at module boundaries. No bare print/console.log.
- Before writing a UI component, check `vault/Components.md`. If it exists, use it.
  If it does not, propose adding it — do not write a one-off.

## 4. Delegation

| Need | Use |
|---|---|
| Procedural knowledge | Skill (`.claude/skills/`) |
| Isolated or parallel work | Subagent (`.claude/agents/`) |
| A rule that must not be broken | Hook (`.claude/hooks/`) |

Subagents exist to keep exploration out of the main context. Delegate research,
test writing, and verification. Do not do them inline.

## 5. Model tiering

Planning and verification use the strongest model. Implementation uses a smaller one —
the plan is already complete, so implementation is transcription. If a small model cannot
implement the plan, the plan was underspecified. Fix the plan, do not escalate the model.

## 6. Gated operations — require explicit human instruction, every time

- `git push`, `git commit`, `git merge`, opening a PR
- Any database write outside the sandbox container
- Migrations against anything but the sandbox
- Adding dependencies
- Deploying to staging or production
- Deleting files outside the current working set

You are running in auto-accept mode. The deny rules in `settings.json` are approximate and
have holes. Do not attempt to route around a gate — request approval explicitly.

## 7. Database

Exactly one database is reachable: the local container at `localhost:5433`.
There is no production connection string in this environment, by design.
Schema changes are emitted as migration files under `app/backend/migrations/`.
You never apply a migration to a shared database.

## 8. Definition of done

Implementation → tests pass → linter clean → `verifier` subagent passes → confidence
score recorded. The `Stop` hook blocks completion until the verifier has passed for the
current change set.

## 9. Saving tokens and switching models

- **Switching models**: `/model` opens the picker (Sonnet 5, Opus 4.8, Haiku 4.5, etc.).
  `/fast` toggles fast mode on Opus tiers (faster output, not a smaller model). Don't
  manually override the tiering in §5 unless a plan keeps failing on the small model —
  fix the plan first, per §5.
- **Don't read the whole repo** (§1). Load only routed Vault files, the modules you're
  touching, and recent changes.
- **Delegate exploration.** Use the `Explore` agent for anything needing more than ~3
  greps; use `general-purpose` for multi-step research. Keeps large search results out of
  the main context. Don't duplicate a search you've already handed to a subagent.
- **Prefer targeted reads**: `Read` with `offset`/`limit` on large files, `grep`/`Grep`
  first to find the line, instead of pulling a whole file in.
- **Use skills instead of re-deriving procedure** — a skill (`.claude/skills/`) encodes a
  known procedure once; invoking it is cheaper than rediscovering the steps each time.
- **Batch independent tool calls** in one turn rather than serial round trips.
- Reserve `Workflow` multi-agent fan-out for explicitly-requested comprehensive
  audits/migrations, not routine edits — it can spawn many agents and burn tokens fast.