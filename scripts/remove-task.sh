#!/usr/bin/env bash
# Remove a task from the queue.
# Usage: remove-task.sh <task-id> [--force]
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

TASK_ID="${1:-}"
FORCE="${2:-}"

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: /autocc:remove <task-id> [--force]" >&2
  exit 1
fi

# Verify task exists
TASK=$(jq -r --arg id "$TASK_ID" '.features[] | select(.id == $id) // empty' "$FEATURE_FILE")
if [[ -z "$TASK" ]]; then
  echo "❌ Task $TASK_ID not found." >&2
  exit 1
fi

# Check if in_progress
TASK_STATUS=$(echo "$TASK" | jq -r '.status')
if [[ "$TASK_STATUS" == "in_progress" && "$FORCE" != "--force" ]]; then
  echo "⚠️  Task $TASK_ID is in progress. Use --force to remove it." >&2
  exit 1
fi

# Check if other tasks depend on this one
DEPENDENTS=$(jq -r --arg id "$TASK_ID" '[.features[] | select(.dependencies[]? == $id) | .id] | join(", ")' "$FEATURE_FILE")
if [[ -n "$DEPENDENTS" && "$FORCE" != "--force" ]]; then
  echo "⚠️  Tasks [$DEPENDENTS] depend on $TASK_ID. Use --force to remove anyway." >&2
  exit 1
fi

TASK_TITLE=$(echo "$TASK" | jq -r '.title')

acquire_lock
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TEMP_FILE=$(mktemp)
jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" '
  .features |= map(select(.id != $id)) | .updated_at = $ts
' "$FEATURE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$FEATURE_FILE"

echo "🗑️  Task removed: $TASK_ID - $TASK_TITLE"
