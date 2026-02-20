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
  echo "❌ jq is required but not installed. Install with: brew install jq" >&2
  exit 1
fi

# Parse arguments
TITLE=""
DESCRIPTION=""
PRIORITY=0
DEPENDENCIES="[]"
CRITERIA="[]"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --priority)
      PRIORITY="$2"; shift 2 ;;
    --depends)
      DEPENDENCIES=$(echo "$2" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
      shift 2 ;;
    --criteria)
      shift
      CRITERIA_ITEMS=()
      while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
        CRITERIA_ITEMS+=("$1")
        shift
      done
      if [[ ${#CRITERIA_ITEMS[@]} -gt 0 ]]; then
        CRITERIA=$(printf '%s\n' "${CRITERIA_ITEMS[@]}" | jq -R . | jq -s .)
      fi
      ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

TITLE="${POSITIONAL[0]:-}"
DESCRIPTION="${POSITIONAL[1]:-$TITLE}"

if [[ -z "$TITLE" ]]; then
  echo "Usage: /autocc:add \"title\" \"description\" [--priority N] [--depends F001,F002] [--criteria \"c1\" \"c2\"]" >&2
  exit 1
fi

# Generate next ID
LAST_ID=$(jq -r '.features[-1].id // "F000"' "$FEATURE_FILE")
NEXT_NUM=$(( ${LAST_ID#F} + 1 ))
NEXT_ID=$(printf "F%03d" "$NEXT_NUM")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ "$PRIORITY" -eq 0 ]]; then
  PRIORITY=$NEXT_NUM
fi

# Add task
acquire_lock
TEMP_FILE=$(mktemp)
jq --arg id "$NEXT_ID" \
   --arg title "$TITLE" \
   --arg desc "$DESCRIPTION" \
   --argjson priority "$PRIORITY" \
   --argjson deps "$DEPENDENCIES" \
   --argjson criteria "$CRITERIA" \
   --arg ts "$TIMESTAMP" \
   '.features += [{
     id: $id,
     title: $title,
     description: $desc,
     status: "pending",
     priority: $priority,
     acceptance_criteria: $criteria,
     dependencies: $deps,
     assigned_at: null,
     completed_at: null,
     attempt_count: 0,
     max_attempts: 3,
     notes: ""
   }] | .updated_at = $ts' "$FEATURE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$FEATURE_FILE"

echo "✅ Task added: $NEXT_ID - $TITLE"
echo "   Priority: $PRIORITY"
echo "   Description: $DESCRIPTION"
echo "   Status: pending"
