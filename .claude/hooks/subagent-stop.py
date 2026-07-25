#!/usr/bin/env python3
"""SubagentStop: the verifier's own completion sets the gate flag.
Matcher-less, so we check which agent finished."""
import json, os, sys

data = json.load(sys.stdin)
root = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
agent = (data.get("agent_type") or data.get("subagent_type") or "").lower()

if "verifier" in agent:
    transcript = json.dumps(data).lower()
    if "verdict: pass" in transcript:
        open(os.path.join(root, ".claude/state/verified.flag"), "w").write(agent)
    else:
        print("Verifier did not return 'VERDICT: PASS'. Address the findings and re-run it.",
              file=sys.stderr)
        sys.exit(2)
sys.exit(0)
