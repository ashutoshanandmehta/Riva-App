#!/usr/bin/env python3
"""PostToolUseFailure: append the failure to dynamic memory so it is not repeated."""
import json, os, sys, datetime

data = json.load(sys.stdin)
root = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
tool = data.get("tool_name", "?")
err = str(data.get("tool_response") or data.get("error") or "")[:400].replace("\n", " ")
stamp = datetime.date.today().isoformat()
with open(os.path.join(root, "vault", "DynamicMemory.md"), "a") as fh:
    fh.write(f"\n- [{stamp}] failure in `{tool}`: {err}\n")
sys.exit(0)
