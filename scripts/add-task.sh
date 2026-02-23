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
PRIORITY=""
ROLE="developer"
DEPENDENCIES="[]"
CRITERIA="[]"
PARENT_ID=""

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --priority)
      PRIORITY="$2"; shift 2 ;;
    --role)
      ROLE="$2"; shift 2 ;;
    --parent)
      PARENT_ID="$2"; shift 2 ;;
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
  echo "Usage: /autocc:add \"title\" \"description\" [--priority N] [--role ROLE] [--parent PARENT_ID] [--depends F001,F002] [--criteria \"c1\" \"c2\"]" >&2
  exit 1
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Generate task ID
if [[ -n "$PARENT_ID" ]]; then
  # Validate parent exists
  PARENT_EXISTS=$(jq -r --arg id "$PARENT_ID" '[.features[] | select(.id == $id)] | length' "$FEATURE_FILE")
  if [[ "$PARENT_EXISTS" -eq 0 ]]; then
    echo "❌ Parent task $PARENT_ID not found." >&2
    exit 1
  fi
  # Subtask ID: F001.1, F001.2, ...
  LAST_SUB=$(jq -r --arg pid "$PARENT_ID" '
    [.features[] | select(.parent_id == $pid) | .id |
     split(".") | .[-1] | tonumber] | max // 0
  ' "$FEATURE_FILE")
  NEXT_SUB=$((LAST_SUB + 1))
  NEXT_ID="${PARENT_ID}.${NEXT_SUB}"
  # Inherit parent priority if not specified
  if [[ -z "$PRIORITY" ]]; then
    PRIORITY=$(jq -r --arg id "$PARENT_ID" '.features[] | select(.id == $id) | .priority' "$FEATURE_FILE")
  fi
else
  # Top-level task ID: F001, F002, ...
  LAST_ID=$(jq -r '[.features[] | select(.parent_id == null or .parent_id == "") | .id // "F000"] | map(select(test("^F[0-9]+$"))) | sort | last // "F000"' "$FEATURE_FILE")
  NEXT_NUM=$(( 10#${LAST_ID#F} + 1 ))
  NEXT_ID=$(printf "F%03d" "$NEXT_NUM")
fi

# Validate dependency IDs exist
if [[ "$DEPENDENCIES" != "[]" ]]; then
  EXISTING_IDS=$(jq -r '[.features[].id] | join(",")' "$FEATURE_FILE")
  INVALID_IDS=$(echo "$DEPENDENCIES" | jq -r '.[]' | while read -r dep_id; do
    if [[ ",$EXISTING_IDS," != *",$dep_id,"* ]]; then
      echo "$dep_id"
    fi
  done)
  if [[ -n "$INVALID_IDS" ]]; then
    echo "❌ Unknown dependency IDs: $INVALID_IDS" >&2
    exit 1
  fi
fi

if [[ -z "$PRIORITY" ]]; then
  NEXT_NUM_FOR_PRI=$(jq '.features | length + 1' "$FEATURE_FILE")
  PRIORITY=$NEXT_NUM_FOR_PRI
fi

# Add task
acquire_lock
TEMP_FILE=$(mktemp)
PARENT_ID_JSON="${PARENT_ID:-null}"
if [[ "$PARENT_ID_JSON" != "null" ]]; then
  PARENT_ID_JSON="\"$PARENT_ID_JSON\""
fi
jq --arg id "$NEXT_ID" \
   --arg title "$TITLE" \
   --arg desc "$DESCRIPTION" \
   --argjson priority "$PRIORITY" \
   --arg role "$ROLE" \
   --argjson parent_id "$PARENT_ID_JSON" \
   --argjson deps "$DEPENDENCIES" \
   --argjson criteria "$CRITERIA" \
   --arg ts "$TIMESTAMP" \
   '.features += [{
     id: $id,
     title: $title,
     description: $desc,
     status: "pending",
     priority: $priority,
     role: $role,
     parent_id: $parent_id,
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
if [[ -n "$PARENT_ID" ]]; then
  echo "   Parent: $PARENT_ID"
fi
echo "   Role: $ROLE"
echo "   Priority: $PRIORITY"
echo "   Description: $DESCRIPTION"
echo "   Status: pending"
