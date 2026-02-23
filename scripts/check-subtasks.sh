#!/usr/bin/env bash
# Check subtask completion status and sync parent task accordingly.
# - All subtasks done → parent task done
# - Any subtask failed → parent task failed (triggers failure propagation)
set -euo pipefail

FEATURE_FILE="${1:-.autonomy/feature_list.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lock-utils.sh"

if [[ ! -f "$FEATURE_FILE" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

# Find all parent IDs that have subtasks
PARENT_IDS=$(jq -r '[.features[] | select(.parent_id != null and .parent_id != "") | .parent_id] | unique | .[]' "$FEATURE_FILE" 2>/dev/null || true)

if [[ -z "$PARENT_IDS" ]]; then
  exit 0
fi

for PID in $PARENT_IDS; do
  PARENT_STATUS=$(jq -r --arg id "$PID" '.features[] | select(.id == $id) | .status' "$FEATURE_FILE" 2>/dev/null || echo "")

  # Skip already done or failed parents
  [[ "$PARENT_STATUS" == "done" || "$PARENT_STATUS" == "failed" ]] && continue

  TOTAL=$(jq --arg pid "$PID" '[.features[] | select(.parent_id == $pid)] | length' "$FEATURE_FILE")
  DONE_COUNT=$(jq --arg pid "$PID" '[.features[] | select(.parent_id == $pid and .status == "done")] | length' "$FEATURE_FILE")
  FAILED_COUNT=$(jq --arg pid "$PID" '[.features[] | select(.parent_id == $pid and .status == "failed")] | length' "$FEATURE_FILE")

  if [[ $FAILED_COUNT -gt 0 ]]; then
    # Subtask failed → parent failed
    acquire_lock
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    TEMP=$(mktemp)
    jq --arg id "$PID" --arg ts "$TIMESTAMP" '
      .features |= map(if .id == $id then .status = "failed" | .completed_at = $ts | .notes = "Subtask(s) failed" else . end) | .updated_at = $ts
    ' "$FEATURE_FILE" > "$TEMP"
    mv "$TEMP" "$FEATURE_FILE"
    release_lock
    echo "❌ Parent $PID marked failed (subtask failure)"
    "$SCRIPT_DIR/propagate-failure.sh" "$PID" 2>/dev/null || true
  elif [[ $DONE_COUNT -eq $TOTAL ]]; then
    # All subtasks done → parent done
    acquire_lock
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    TEMP=$(mktemp)
    jq --arg id "$PID" --arg ts "$TIMESTAMP" '
      .features |= map(if .id == $id then .status = "done" | .completed_at = $ts else . end) | .updated_at = $ts
    ' "$FEATURE_FILE" > "$TEMP"
    mv "$TEMP" "$FEATURE_FILE"
    release_lock
    echo "✅ Parent $PID auto-completed (all subtasks done)"
  fi
done
