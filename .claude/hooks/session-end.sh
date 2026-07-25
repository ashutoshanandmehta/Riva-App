#!/usr/bin/env bash
# SessionEnd: flush state. Anything that must happen after merge belongs in CI, not here.
set -euo pipefail
R="${CLAUDE_PROJECT_DIR:-$(pwd)}"
{
  echo ""
  echo "## Session ended $(date -u +%FT%TZ)"
  git -C "$R" log --oneline -5 2>/dev/null | sed 's/^/  /' || true
} >> "$R/vault/DynamicMemory.md"
rm -f "$R/.claude/state/dirty.flag" "$R/.claude/state/verified.flag"
exit 0
