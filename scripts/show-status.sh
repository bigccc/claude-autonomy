#!/usr/bin/env bash
set -euo pipefail

FEATURE_FILE=".autonomy/feature_list.json"

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "❌ Autonomy system not initialized. Run /autocc:init first." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq is required. Install with: brew install jq" >&2
  exit 1
fi

echo "📊 Autonomy Status"
echo "═══════════════════════════════════════"

PROJECT=$(jq -r '.project' "$FEATURE_FILE")
echo "Project: $PROJECT"
echo ""

TOTAL=$(jq '.features | length' "$FEATURE_FILE")
PENDING=$(jq '[.features[] | select(.status == "pending")] | length' "$FEATURE_FILE")
IN_PROGRESS=$(jq '[.features[] | select(.status == "in_progress")] | length' "$FEATURE_FILE")
DONE=$(jq '[.features[] | select(.status == "done")] | length' "$FEATURE_FILE")
FAILED=$(jq '[.features[] | select(.status == "failed")] | length' "$FEATURE_FILE")
BLOCKED=$(jq '[.features[] | select(.status == "blocked")] | length' "$FEATURE_FILE")

echo "Tasks: $TOTAL total"
echo "  Pending:     $PENDING"
echo "  In Progress: $IN_PROGRESS"
echo "  Done:        $DONE"
echo "  Failed:      $FAILED"
echo "  Blocked:     $BLOCKED"
echo ""

# Show current in-progress task
if [[ $IN_PROGRESS -gt 0 ]]; then
  echo "Current task:"
  jq -r '.features[] | select(.status == "in_progress") | "  \(.id) [\(.role // "developer")] - \(.title)"' "$FEATURE_FILE"
  echo ""
fi

# Show next pending task
if [[ $PENDING -gt 0 ]]; then
  DONE_IDS=$(jq '[.features[] | select(.status == "done") | .id]' "$FEATURE_FILE")
  NEXT=$(jq -r --argjson done "$DONE_IDS" '
    [.features[] | select(.status == "pending") |
     select((.dependencies | length == 0) or (.dependencies | all(. as $d | $done | index($d) != null)))] |
    sort_by(.priority) | .[0] // empty |
    "\(.id) - \(.title)"
  ' "$FEATURE_FILE" 2>/dev/null || echo "None (all pending tasks have unmet dependencies)")
  echo "Next eligible task: $NEXT"
  echo ""
fi

# Show all tasks
echo "All tasks:"
jq -r '.features[] | "  [\(.status | if . == "done" then "✅" elif . == "in_progress" then "🔄" elif . == "failed" then "❌" elif . == "blocked" then "🚫" else "⏳" end)] \(.id) [\(.role // "developer")] - \(.title)"' "$FEATURE_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check loop state
LOOP_STATE=".claude/autonomy-loop.local.md"
if [[ -f "$LOOP_STATE" ]]; then
  ITERATION=$(sed -n '/^---$/,/^---$/p' "$LOOP_STATE" | grep -m1 "^iteration:" | sed 's/^iteration:[[:space:]]*//' | tr -d '[:space:]')
  echo ""
  echo "🔄 Autonomous loop is ACTIVE (iteration: $ITERATION)"
fi

# Check for circular dependencies
"$SCRIPT_DIR/check-cycles.sh" "$FEATURE_FILE" 2>&1 || true

echo "═══════════════════════════════════════"
