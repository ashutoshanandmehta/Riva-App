---
description: Prepare a PR body without pushing anything
---
Prepare release artifacts for the current change set. Do not run git commit, push, or gh pr — they are blocked.

Produce, as text for me to review:
1. Commit message (conventional commits).
2. PR title and body: what changed, why, blast radius from impact-analyzer, test evidence.
3. Migration notes, if a migration was generated.
4. Changelog entry.
5. The verifier's confidence score.

Then stop and wait for my explicit instruction to commit.
