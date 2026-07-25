#!/usr/bin/env bash
# PreCompact: persist what compaction would otherwise discard.
set -euo pipefail
R="${CLAUDE_PROJECT_DIR:-$(pwd)}"
{
  echo ""
  echo "## Context checkpoint $(date -u +%FT%TZ)"
  echo "Branch: $(git -C "$R" rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)"
  echo "Changed files:"
  git -C "$R" status --porcelain 2>/dev/null | sed 's/^/  /' || true
} >> "$R/vault/DynamicMemory.md"
exit 0
