#!/usr/bin/env python3
"""PreToolUse(Bash): capability gate. Exit 2 blocks; stderr becomes the reason Claude sees.
This is the layer that survives auto-accept mode."""
import json, os, re, sys

data = json.load(sys.stdin)
cmd = (data.get("tool_input") or {}).get("command", "")

# 1. Wrapper detection — deny-lists lose to indirection. Refuse to evaluate what we can't read.
WRAPPERS = [
    (r"\|\s*(bash|sh|zsh)\b",           "piping into a shell"),
    (r"\b(eval|source)\b",              "eval/source"),
    (r"base64\s+(-d|--decode)",         "base64-decoded command"),
    (r"curl[^|]*\|\s*\w*sh",            "curl | sh"),
    (r"\bnohup\b|\bdisown\b|&\s*$",     "backgrounded command"),
]
for pattern, label in WRAPPERS:
    if re.search(pattern, cmd):
        print(f"Blocked: {label} hides the real command from the guard. "
              f"Run the underlying command directly so it can be checked.", file=sys.stderr)
        sys.exit(2)

# 2. Version control — commit/merge/rebase/PR and branch pushes are allowed
# (2026-07-25: the blanket block meant every commit had to be hand-run by the
# human, which cost more than it caught). Two things stay blocked because they
# are the ones that actually destroy work or skip review.
if re.search(r"\bgit\s+push\b.*(--force(?!-with-lease)|(?<!-)\s-f\b|\s\+)", cmd):
    print("Blocked: force-push can destroy pushed history. Use --force-with-lease, "
          "or ask if the history really needs rewriting.", file=sys.stderr)
    sys.exit(2)
if re.search(r"\bgit\s+push\b[^|;&]*\borigin\s+(main|master)\b", cmd):
    print("Blocked: push a branch and open a PR instead of pushing straight to main. "
          "If a direct push to main is genuinely intended, ask first.", file=sys.stderr)
    sys.exit(2)

# 3. Database — the guessing failure mode. Only the sandbox port is reachable.
if re.search(r"\b(psql|mysql|mongosh|redis-cli)\b", cmd):
    sandbox = re.search(r"(localhost|127\.0\.0\.1):5433", cmd)
    if not sandbox:
        print("Blocked: database access must target the sandbox at localhost:5433 explicitly. "
              "If the intended target is ambiguous, ask — do not infer a connection string.",
              file=sys.stderr)
        sys.exit(2)
if re.search(r"(prod|production|staging)[-_.]?(db|database|host)", cmd, re.I):
    print("Blocked: reference to a non-sandbox database.", file=sys.stderr)
    sys.exit(2)

# 4. Destructive filesystem
if re.search(r"\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+(/|~|\$HOME|\*)", cmd):
    print("Blocked: recursive delete outside the working set.", file=sys.stderr)
    sys.exit(2)

# 5. Secrets exfiltration
if re.search(r"\.env\b|\.ssh/|\.aws/|id_rsa|credentials", cmd) and \
   re.search(r"\b(cat|less|head|tail|curl|wget|nc|scp)\b", cmd):
    print("Blocked: reading or transmitting credential files.", file=sys.stderr)
    sys.exit(2)

sys.exit(0)
