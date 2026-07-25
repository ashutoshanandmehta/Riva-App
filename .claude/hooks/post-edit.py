#!/usr/bin/env python3
"""PostToolUse(Edit|Write): format, lint, warn. Cannot undo the write — advisory only."""
import json, os, subprocess, sys

data = json.load(sys.stdin)
path = ((data.get("tool_input") or {}).get("file_path")) or ""
if not path or not os.path.exists(path):
    sys.exit(0)

root = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())

def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None

notes = []
if path.endswith(".py"):
    # ruff lives in the backend venv (uv-managed); fall back to PATH.
    ruff = os.path.join(root, "backend/.venv/bin/ruff")
    ruff = ruff if os.path.exists(ruff) else "ruff"
    run([ruff, "format", path])
    r = run([ruff, "check", path])
    if r and r.returncode != 0:
        notes.append(r.stdout[-1500:])
elif path.endswith(".swift"):
    # swift-format / swiftformat are optional; run() no-ops if absent.
    if run(["swift-format", "format", "-i", path]) is None:
        run(["swiftformat", path])
elif path.endswith((".ts", ".tsx", ".js", ".jsx", ".json", ".css", ".md")):
    run(["npx", "--no-install", "prettier", "--write", path])
    r = run(["npx", "--no-install", "eslint", path])
    if r and r.returncode != 0:
        notes.append(r.stdout[-1500:])

with open(path) as fh:
    lines = fh.read().splitlines()
if len(lines) > 500:
    notes.append(f"{os.path.basename(path)} is {len(lines)} lines (soft limit 500). "
                 f"Split before it reaches the 1000-line hard limit.")

# Test reminder for backend application code (advisory).
if "backend/app/" in path.replace("\\", "/") and not any(t in path for t in ("test", "spec")):
    notes.append(f"Reminder: consider tests under backend/tests/ for changes to {os.path.basename(path)}.")

if notes:
    print("Post-edit findings:\n" + "\n".join(notes), file=sys.stderr)
    sys.exit(1)   # surfaced to Claude, does not block
sys.exit(0)
