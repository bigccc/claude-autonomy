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

# Find current task — reuse get-next-task-json.sh for consistent logic
# (handles subtask parent skipping, dependency checks, priority sorting)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_ID="${3:-}"

if [[ -n "$TASK_ID" ]]; then
  # Explicit task ID passed — look it up directly
  CURRENT_TASK=$(jq --arg id "$TASK_ID" '[.features[] | select(.id == $id)][0] // null' "$FEATURE_FILE")
else
  # Use shared get-next-task logic
  NEXT_JSON=$("$SCRIPT_DIR/get-next-task-json.sh" "$FEATURE_FILE" 2>/dev/null || true)
  if [[ -n "$NEXT_JSON" && "$NEXT_JSON" != "null" ]]; then
    CURRENT_TASK="$NEXT_JSON"
  else
    CURRENT_TASK="null"
  fi
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
    execution_protocol: "4 phases: Analyze (read code, understand context) → Design (plan approach, write to progress.txt) → Implement (write code, commit) → Verify (test, lint, check acceptance_criteria, mark done)",
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
  parent_task: (if $current.parent_id then
    [.features[] | select(.id == $current.parent_id)][0] // null |
    if . then {id, title, description, notes} else null end
  else null end),
  sibling_tasks: (if $current.parent_id then
    [.features[] | select(.parent_id == $current.parent_id and .id != $current.id) |
     {id, title, status}]
  else [] end),
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
  execution_protocol: "4 phases: Analyze (read code, understand context) → Design (plan approach, write to progress.txt) → Implement (write code, commit) → Verify (test, lint, check acceptance_criteria, mark done)",
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

# Read configurable line limits
RECENT_LINES=20
RELEVANT_LINES=30
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
  CONFIGURED_RECENT=$(jq -r '.compact_recent_progress_lines // empty' "$CONFIG_FILE" 2>/dev/null || true)
  CONFIGURED_RELEVANT=$(jq -r '.compact_relevant_progress_lines // empty' "$CONFIG_FILE" 2>/dev/null || true)
  [[ -n "$CONFIGURED_RECENT" && "$CONFIGURED_RECENT" =~ ^[0-9]+$ ]] && RECENT_LINES=$CONFIGURED_RECENT
  [[ -n "$CONFIGURED_RELEVANT" && "$CONFIGURED_RELEVANT" =~ ^[0-9]+$ ]] && RELEVANT_LINES=$CONFIGURED_RELEVANT
fi

if [[ -f "$PROGRESS_FILE" ]]; then
  # Extract lines related to current task (grep task ID)
  RELEVANT_PROGRESS=$(grep -i "$CURRENT_ID" "$PROGRESS_FILE" 2>/dev/null | tail -"$RELEVANT_LINES" || true)
  # Recent lines for general context
  RECENT_PROGRESS=$(tail -"$RECENT_LINES" "$PROGRESS_FILE" 2>/dev/null || true)
fi

# Merge progress and project index into the JSON
TEMP_FILE=$(mktemp)

PROJECT_INDEX=""
if [[ -f ".autonomy/project_index.md" ]]; then
  PROJECT_INDEX=$(head -80 ".autonomy/project_index.md" 2>/dev/null || true)
fi

jq --arg rel "$RELEVANT_PROGRESS" --arg rec "$RECENT_PROGRESS" --arg idx "$PROJECT_INDEX" '
  .relevant_progress = $rel |
  .recent_progress = $rec |
  .project_index = $idx
' "$OUTPUT_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$OUTPUT_FILE"
