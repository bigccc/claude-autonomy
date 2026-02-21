#!/usr/bin/env bash
# Generate a compact context file for the current task.
# Strips unnecessary details from feature_list.json and progress.txt
# to reduce token usage in AI prompts.
#
# Usage: compact-context.sh [feature_list.json] [progress.txt]
# Output: writes .autonomy/context.compact.json

set -euo pipefail

FEATURE_FILE="${1:-.autonomy/feature_list.json}"
PROGRESS_FILE="${2:-.autonomy/progress.txt}"
CONFIG_FILE=".autonomy/config.json"
OUTPUT_FILE=".autonomy/context.compact.json"

if [[ ! -f "$FEATURE_FILE" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

# Check if compact is enabled (default: true)
if [[ -f "$CONFIG_FILE" ]]; then
  ENABLED=$(jq -r '.context_compact // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  if [[ "$ENABLED" == "false" ]]; then
    # Disabled — remove stale compact file if exists
    rm -f "$OUTPUT_FILE"
    exit 0
  fi
fi

# Find current task (in_progress first, then next pending)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_TASK=$(jq '[.features[] | select(.status == "in_progress")][0] // null' "$FEATURE_FILE")

if [[ "$CURRENT_TASK" == "null" ]]; then
  DONE_IDS=$(jq '[.features[] | select(.status == "done") | .id]' "$FEATURE_FILE")
  CURRENT_TASK=$(jq --argjson done "$DONE_IDS" '
    [.features[] | select(.status == "pending") |
     select((.dependencies | length == 0) or (.dependencies | all(. as $d | $done | index($d) != null)))] |
    sort_by(.priority) | .[0] // null
  ' "$FEATURE_FILE")
fi

if [[ "$CURRENT_TASK" == "null" ]]; then
  # No active task — generate minimal summary only
  jq '{
    current_task: null,
    dependency_tasks: [],
    queue_summary: {
      total: (.features | length),
      done: ([.features[] | select(.status == "done")] | length),
      pending: ([.features[] | select(.status == "pending")] | length),
      failed: ([.features[] | select(.status == "failed")] | length),
      blocked: ([.features[] | select(.status == "blocked")] | length),
      in_progress: ([.features[] | select(.status == "in_progress")] | length)
    },
    other_tasks: [.features[] | {id, title, status}],
    relevant_progress: "",
    recent_progress: ""
  }' "$FEATURE_FILE" > "$OUTPUT_FILE"
  exit 0
fi

CURRENT_ID=$(echo "$CURRENT_TASK" | jq -r '.id')
DEP_IDS=$(echo "$CURRENT_TASK" | jq -r '.dependencies // []')

# Build compact context with jq
jq --argjson current "$CURRENT_TASK" --argjson dep_ids "$DEP_IDS" '
{
  current_task: $current,
  dependency_tasks: [
    .features[] | select(.id as $id | $dep_ids | index($id) != null) |
    {id, title, status, role, notes}
  ],
  queue_summary: {
    total: (.features | length),
    done: ([.features[] | select(.status == "done")] | length),
    pending: ([.features[] | select(.status == "pending")] | length),
    failed: ([.features[] | select(.status == "failed")] | length),
    blocked: ([.features[] | select(.status == "blocked")] | length),
    in_progress: ([.features[] | select(.status == "in_progress")] | length)
  },
  other_tasks: [
    .features[] | select(.id != $current.id) |
    if .status == "done" then {id, title, status}
    else {id, title, status, dependencies}
    end
  ]
}' "$FEATURE_FILE" > "$OUTPUT_FILE"

# Append progress context
RELEVANT_PROGRESS=""
RECENT_PROGRESS=""

if [[ -f "$PROGRESS_FILE" ]]; then
  # Extract lines related to current task (grep task ID)
  RELEVANT_PROGRESS=$(grep -i "$CURRENT_ID" "$PROGRESS_FILE" 2>/dev/null | tail -20 || true)
  # Last 10 lines for general context
  RECENT_PROGRESS=$(tail -10 "$PROGRESS_FILE" 2>/dev/null || true)
fi

# Merge progress into the JSON
TEMP_FILE=$(mktemp)
jq --arg rel "$RELEVANT_PROGRESS" --arg rec "$RECENT_PROGRESS" '
  .relevant_progress = $rel |
  .recent_progress = $rec
' "$OUTPUT_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$OUTPUT_FILE"
