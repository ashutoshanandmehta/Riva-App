#!/usr/bin/env bash
# SessionStart -> stdout is injected as context.
set -euo pipefail
R="${CLAUDE_PROJECT_DIR:-$(pwd)}"

echo "## Project state"
echo "Branch: $(git -C "$R" rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)"
echo "Uncommitted: $(git -C "$R" status --porcelain 2>/dev/null | wc -l | tr -d ' ') file(s)"
echo
echo "### Recent commits"
git -C "$R" log --oneline -8 2>/dev/null || true
echo
echo "### Architecture graph"
sed -n '1,60p' "$R/vault/ArchitectureGraph.md" 2>/dev/null || echo "(missing)"
echo
echo "### Recent decisions"
tail -n 30 "$R/vault/DecisionLog.md" 2>/dev/null || echo "(none)"
echo
echo "### Known failure patterns"
tail -n 30 "$R/vault/DynamicMemory.md" 2>/dev/null || echo "(none)"
echo
echo "### Open TODOs"
grep -rn "TODO:" "$R/backend/app" "$R/ios/Riva" 2>/dev/null | head -10 || true
echo
echo "Reminder: plan before coding; gated ops (push/commit/deploy/migrations) need explicit approval; local DB is the sandbox at localhost:5433."

# reset the per-change verification gate
rm -f "$R/.claude/state/verified.flag" "$R/.claude/state/dirty.flag"
exit 0
