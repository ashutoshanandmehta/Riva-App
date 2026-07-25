#!/usr/bin/env python3
"""PreToolUse(Edit|Write): structural rules enforced before the write lands."""
import json, os, sys

data = json.load(sys.stdin)
ti = data.get("tool_input") or {}
path = ti.get("file_path", "")
content = ti.get("content") or ti.get("new_string") or ""
root = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())

PROTECTED = ("vault/Architecture.md", "vault/Security.md", "vault/API.md",
             "vault/DesignSystem.md", "CLAUDE.md", ".claude/settings.json")
rel = os.path.relpath(path, root) if path.startswith("/") else path
if any(rel.replace("\\", "/").startswith(p) for p in PROTECTED):
    print(f"Blocked: {rel} is static knowledge. Propose the change to the human instead of editing it.",
          file=sys.stderr)
    sys.exit(2)

if content.count("\n") > 1000:
    print("Blocked: file exceeds the 1000-line hard limit. Split it into modules.", file=sys.stderr)
    sys.exit(2)

# mark the change set unverified
open(os.path.join(root, ".claude/state/dirty.flag"), "w").write(rel)
try:
    os.remove(os.path.join(root, ".claude/state/verified.flag"))
except FileNotFoundError:
    pass
sys.exit(0)
