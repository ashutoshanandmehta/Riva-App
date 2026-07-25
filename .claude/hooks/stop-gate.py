#!/usr/bin/env python3
"""Stop: ADVISORY verification reminder. Never traps the turn — Riva has no
mandatory test gate yet. Prints a one-line nudge on unverified changes and
exits 0. To re-arm the hard gate once a real test suite exists, change the
`sys.exit(0)` in the block below to `sys.exit(2)`."""
import json, os, sys

data = json.load(sys.stdin)
root = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())

if data.get("stop_hook_active"):
    sys.exit(0)   # already looping; do not trap

dirty = os.path.join(root, ".claude/state/dirty.flag")
verified = os.path.join(root, ".claude/state/verified.flag")

if os.path.exists(dirty) and not os.path.exists(verified):
    print("Reminder: code changed this turn but the verifier has not passed. "
          "Consider running `/verify` before wrapping up.", file=sys.stderr)
    # Advisory: clear the flags and let the turn end. Flip to sys.exit(2) to
    # make verification mandatory.
    for f in (dirty, verified):
        try:
            os.remove(f)
        except FileNotFoundError:
            pass
    sys.exit(0)

for f in (dirty, verified):
    try:
        os.remove(f)
    except FileNotFoundError:
        pass
sys.exit(0)
