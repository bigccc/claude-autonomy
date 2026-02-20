#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lock-utils.sh"

FEATURE_FILE=".autonomy/feature_list.json"

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "❌ Autonomy system not initialized. Run /autocc:init first." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq is required. Install with: brew install jq" >&2
  exit 1
fi

# Find next task using shared script
NEXT_TASK=$("$SCRIPT_DIR/get-next-task-json.sh" "$FEATURE_FILE" 2>/dev/null || true)

if [[ -z "$NEXT_TASK" || "$NEXT_TASK" == "null" ]]; then
  echo "✅ No eligible pending tasks. All done or blocked!"
  "$SCRIPT_DIR/check-cycles.sh" "$FEATURE_FILE" 2>&1 || true
  exit 0
fi

TASK_ID=$(echo "$NEXT_TASK" | jq -r '.id')
TASK_STATUS=$(echo "$NEXT_TASK" | jq -r '.status')

if [[ "$TASK_STATUS" == "in_progress" ]]; then
  echo "🔄 Resuming in-progress task:"
  echo "$NEXT_TASK" | jq -r '"  ID: \(.id)\n  Title: \(.title)\n  Description: \(.description)\n  Criteria: \(.acceptance_criteria | join(", "))\n  Attempt: \(.attempt_count + 1)/\(.max_attempts)"'
  # Warn about uncommitted changes from a possibly interrupted session
  if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
    DIRTY=$(git status --porcelain 2>/dev/null || true)
    if [[ -n "$DIRTY" ]]; then
      echo ""
      echo "⚠️  Uncommitted changes detected (possibly from interrupted session):"
      echo "$DIRTY" | head -10
      echo "   Review before continuing. Consider: git stash or git checkout ."
    fi
  fi
  exit 0
fi

# Mark as in_progress
acquire_lock
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TEMP_FILE=$(mktemp)
jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" '
  .features |= map(if .id == $id then .status = "in_progress" | .assigned_at = $ts else . end) |
  .updated_at = $ts
' "$FEATURE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$FEATURE_FILE"

echo "📋 Next task assigned:"
echo "$NEXT_TASK" | jq -r '"  ID: \(.id)\n  Title: \(.title)\n  Description: \(.description)\n  Criteria: \(.acceptance_criteria | join(", "))\n  Dependencies: \(if (.dependencies | length) > 0 then (.dependencies | join(", ")) else "none" end)"'
