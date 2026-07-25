---
name: architecture-rules
description: The project's non-negotiable engineering rules and why each exists. Load when writing or reviewing code, deciding where a file belongs, sizing a module, touching the database, or when a hook has blocked an action and the reason is unclear.
---

# Architecture Rules

Each rule below is enforced by a hook. This file explains the reasoning so you comply
deliberately rather than by trial and error.

## Files
Soft limit 500 lines, hard limit 1000. Enforced by `guard-edit.py` (blocks the write).
Reason: modules that exceed this stop being reusable and stop fitting in a context window
alongside their neighbours.

## Existing code
Do not modify working code the plan did not name. Flagged by `verifier`.
Reason: drive-by edits are the largest source of regressions in autonomous runs, and they
are invisible in a large diff.

## Components
Check `vault/Components.md` before writing UI. Enforced by `verifier`.
Reason: a catalogue only prevents duplication if it is consulted before, not after.

## Database
Only `localhost:5433` is reachable. Enforced by `guard-bash.py`.
Reason: given an ambiguous target, a model picks one by inference rather than asking.
The mitigation is that no other connection string exists in this environment.

## Version control
`git push`, `commit`, `merge`, and `gh pr` are blocked. Enforced by `guard-bash.py`.
Reason: an agent that can commit and push makes bad state permanent and shared before
a human reads it.

## Shell wrappers
`eval`, `curl | sh`, base64-decoded commands, and pipes into a shell are blocked outright.
Reason: the guard can only check commands it can read. Indirection is refused rather than
inspected.

## Static vault files
Architecture.md, Security.md, API.md, DesignSystem.md cannot be edited by an agent.
Propose changes in your output instead.

## Completion
The `Stop` hook blocks the end of a turn while code is modified and the verifier has not
returned `VERDICT: PASS`. Run the verifier before you try to finish.
