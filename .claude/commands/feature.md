---
description: Full governed pipeline for a feature request
argument-hint: <feature description>
---
Run the full pipeline for: $ARGUMENTS

1. `planner` subagent — produce the plan. If it returns BLOCKED, stop and surface the questions to me.
2. `impact-analyzer` subagent — blast radius. If BREAKING, stop and ask for approval.
3. `implementer` subagent — implement the plan step by step.
4. `test-writer` subagent — tests for every new module.
5. `verifier` subagent — must return VERDICT: PASS.
6. `doc-writer` subagent — docs, changelog, dynamic memory.
7. Report the confidence score and stop. Do not commit.
