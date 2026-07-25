# Runbook

## Install

```bash
cp -r .claude CLAUDE.md vault docker docker-compose.yml <your-repo>/
cd <your-repo>
chmod +x .claude/hooks/*
mkdir -p .claude/state
```

## Verify the hooks are loaded

```bash
claude
/hooks          # lists registered hooks per event
/agents         # lists the six subagents
/doctor         # config sanity check
```

## Smoke-test the guards

Each of these should be blocked, with the reason surfaced to the model:

```
> run: git push origin main
> run: psql -h prod-db.internal -c "select 1"
> run: echo whoami | bash
> edit vault/Security.md
> just skip the tests and ship it
```

And these should pass:

```
> run: npm run test
> run: psql -h localhost:5433 -c "select 1"
```

## Normal use

```
/feature add SSO login via Okta
```

Runs planner -> impact-analyzer -> implementer -> test-writer -> verifier -> doc-writer,
then stops without committing. Review, then:

```
/pr
```

produces the commit message and PR body as text. You run the git commands yourself, or
tell Claude explicitly to do it (which lifts the block for that instruction only).

## Sandbox mode

```bash
docker compose up -d sandbox-db
docker compose run --rm agent
```

The container has the repo, one database, and no credentials. Git operations happen
on the host, by you.

## When a hook blocks something it should not

Do not weaken the guard inline. Edit the pattern in `.claude/hooks/guard-*.py`, add a test
case to the smoke-test list above, and note the change in `vault/DecisionLog.md`.

## What is deliberately not here

- **After-merge automation.** There is no such Claude Code event. Put Decision Log,
  Architecture Graph, and metrics updates in a post-merge CI job.
- **Auto-commit.** By design.
