#!/usr/bin/env bash
set -euo pipefail

FEATURE_FILE=".autonomy/feature_list.json"
LOOP_STATE=".claude/autonomy-loop.local.md"

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "❌ Autonomy system not initialized. Run /autocc:init first." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq is required. Install with: brew install jq" >&2
  exit 1
fi

# Parse arguments
MAX_ITERATIONS=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Check pending tasks
PENDING=$(jq '[.features[] | select(.status == "pending" or .status == "in_progress")] | length' "$FEATURE_FILE")
if [[ $PENDING -eq 0 ]]; then
  echo "✅ No pending tasks. All done!"
  exit 0
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Create loop state file (markdown with YAML frontmatter, same pattern as ralph-wiggum)
mkdir -p .claude
cat > "$LOOP_STATE" <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
started_at: "$TIMESTAMP"
---

Autonomy loop active. Execute the current task from .autonomy/feature_list.json following the Autonomy Protocol.
EOF

echo "🔄 Autonomous loop activated!"
echo ""
echo "Iteration: 1"
echo "Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)"
echo "Pending tasks: $PENDING"
echo ""

# Show first task
DONE_IDS=$(jq '[.features[] | select(.status == "done") | .id]' "$FEATURE_FILE")
CURRENT=$(jq -r '[.features[] | select(.status == "in_progress")][0] | "\(.id) - \(.title)"' "$FEATURE_FILE" 2>/dev/null || echo "")

if [[ -z "$CURRENT" || "$CURRENT" == "null - null" ]]; then
  CURRENT=$(jq -r --argjson done "$DONE_IDS" '
    [.features[] | select(.status == "pending") |
     select((.dependencies | length == 0) or (.dependencies | all(. as $d | $done | index($d) != null)))] |
    sort_by(.priority) | .[0] |
    "\(.id) - \(.title)"
  ' "$FEATURE_FILE" 2>/dev/null || echo "none")
fi

echo "First task: $CURRENT"
echo ""
echo "The Stop hook will automatically advance to the next task when you finish."
echo "To cancel: /autocc:stop"
echo ""
echo "Begin by reading .autonomy/progress.txt and .autonomy/feature_list.json."
