# Saving tokens and switching models in Claude Code

Practical notes for this repo. Not project architecture — just how to use the CLI efficiently.

## Switching models

- `/model` — open the picker and switch the active model for the session (e.g. Sonnet 5, Opus 4.8, Haiku 4.5).
- `/fast` — toggles fast mode (Opus with faster output) on Opus tiers. Does not downgrade to a smaller model, it changes latency/throughput characteristics.
- Per-task model tiering already happens automatically for `/feature`: planning and verification run on the strongest model, implementation runs on a smaller one, per this repo's `CLAUDE.md` §5. Don't override this manually unless the small model keeps failing on a plan — fix the plan first.
- Subagents and Workflow `agent()` calls can override the model per call (`model` param) — useful for cheap mechanical passes (e.g. Haiku for a rote rename) vs. hard judgment calls (Opus for adversarial verification).

## Saving tokens

- **Don't read the whole repo.** `CLAUDE.md` §1 already says this — load only the Vault files the hook routes in, plus the modules you're touching.
- **Delegate exploration.** Use the `Explore` agent (or `general-purpose` for multi-step research) for anything that would take more than ~3 greps — it keeps large search results out of your main context and returns a distilled answer.
- **Prefer targeted reads.** Use `Read` with `offset`/`limit` on large files instead of pulling the whole thing in; use `grep`/`Grep` to find the line first.
- **Let `/compact` do its job.** The conversation auto-summarizes as it approaches the context limit — you don't need to manually trim history or restart sessions to save tokens.
- **Use skills instead of re-deriving procedure.** A skill (`.claude/skills/`) encodes a known procedure once; invoking it is cheaper than re-explaining or re-discovering the steps each time.
- **Avoid duplicate work.** If you hand a search off to a subagent, don't also run the same greps yourself — that's the token cost paid twice.
- **Batch independent tool calls** in one turn instead of serial back-and-forth round trips; each round trip re-sends context.
- **Prompt caching** — the Claude API caches unchanged prefix content for a few minutes; keeping requests within that window (rather than idling past it) avoids a full-price re-read of context. This matters more for scheduled/looped work (see the `loop` skill) than for interactive sessions.
- **Only use `Workflow`/multi-agent fan-out when it's actually warranted** — it can spawn many agents and burn tokens fast; reserve it for explicitly-requested comprehensive audits or migrations, not routine edits.
