#!/usr/bin/env bash
# Edit an existing task's fields.
# Usage: edit-task.sh <task-id> [--title "new title"] [--desc "new desc"] [--priority N] [--status STATUS]
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
if [[ -z "$TASK_ID" ]]; then
  echo "Usage: /autocc:edit <task-id> [--title \"...\"] [--desc \"...\"] [--priority N] [--status STATUS]" >&2
  exit 1
fi
shift

# Verify task exists
EXISTS=$(jq -r --arg id "$TASK_ID" '[.features[] | select(.id == $id)] | length' "$FEATURE_FILE")
if [[ "$EXISTS" -eq 0 ]]; then
  echo "❌ Task $TASK_ID not found." >&2
  exit 1
fi

# Parse arguments
UPDATES=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --title)
      UPDATES="$UPDATES | if .id == \$id then .title = \$title else . end"
      TITLE="$2"; shift 2 ;;
    --desc|--description)
      UPDATES="$UPDATES | if .id == \$id then .description = \$desc else . end"
      DESC="$2"; shift 2 ;;
    --priority)
      UPDATES="$UPDATES | if .id == \$id then .priority = \$priority else . end"
      PRIORITY="$2"; shift 2 ;;
    --status)
      UPDATES="$UPDATES | if .id == \$id then .status = \$status else . end"
      STATUS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$UPDATES" ]]; then
  echo "Nothing to update. Use --title, --desc, --priority, or --status." >&2
  exit 1
fi

acquire_lock
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TEMP_FILE=$(mktemp)

JQ_ARGS=(--arg id "$TASK_ID" --arg ts "$TIMESTAMP")
[[ -n "${TITLE:-}" ]] && JQ_ARGS+=(--arg title "$TITLE")
[[ -n "${DESC:-}" ]] && JQ_ARGS+=(--arg desc "$DESC")
[[ -n "${PRIORITY:-}" ]] && JQ_ARGS+=(--argjson priority "$PRIORITY")
[[ -n "${STATUS:-}" ]] && JQ_ARGS+=(--arg status "$STATUS")

jq "${JQ_ARGS[@]}" ".features |= map(. $UPDATES) | .updated_at = \$ts" "$FEATURE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$FEATURE_FILE"

echo "✅ Task $TASK_ID updated."
jq -r --arg id "$TASK_ID" '.features[] | select(.id == $id) | "  ID: \(.id)\n  Title: \(.title)\n  Status: \(.status)\n  Priority: \(.priority)\n  Description: \(.description)"' "$FEATURE_FILE"
