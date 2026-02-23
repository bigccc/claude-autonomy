#!/usr/bin/env bash
# Find the next eligible task and output it as JSON.
# Outputs empty string if no task found.
# Does NOT modify feature_list.json.
set -euo pipefail

FEATURE_FILE="${1:-.autonomy/feature_list.json}"

if [[ ! -f "$FEATURE_FILE" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

# Find parent IDs that have subtasks (these should be skipped)
HAS_CHILDREN=$(jq '[.features[] | select(.parent_id != null and .parent_id != "") | .parent_id] | unique' "$FEATURE_FILE")

# Check in_progress first (but skip parents with subtasks)
TASK=$(jq -r --argjson has_children "$HAS_CHILDREN" '
  [.features[] | select(.status == "in_progress") |
   select(.id as $id | $has_children | index($id) | not)][0] // empty
' "$FEATURE_FILE")

if [[ -z "$TASK" || "$TASK" == "null" ]]; then
  DONE_IDS=$(jq '[.features[] | select(.status == "done") | .id]' "$FEATURE_FILE")
  TASK=$(jq --argjson done "$DONE_IDS" --argjson has_children "$HAS_CHILDREN" '
    [.features[] | select(.status == "pending") |
     select(.id as $id | $has_children | index($id) | not) |
     select((.dependencies | length == 0) or (.dependencies | all(. as $d | $done | index($d) != null)))] |
    sort_by(.priority) | .[0] // empty
  ' "$FEATURE_FILE")
fi

if [[ -n "$TASK" && "$TASK" != "null" ]]; then
  echo "$TASK"
fi
