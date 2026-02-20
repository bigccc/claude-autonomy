#!/usr/bin/env bash
# Propagate failure: when a task is failed, mark all direct dependents as blocked.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lock-utils.sh"

FEATURE_FILE=".autonomy/feature_list.json"
FAILED_ID="${1:-}"

if [[ -z "$FAILED_ID" ]]; then
  echo "Usage: propagate-failure.sh <task-id>" >&2
  exit 1
fi

if [[ ! -f "$FEATURE_FILE" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

# Find tasks that depend on the failed task and are still pending/in_progress
DEPENDENTS=$(jq -r --arg id "$FAILED_ID" '
  [.features[] |
   select(.status == "pending" or .status == "in_progress") |
   select(.dependencies[]? == $id) |
   .id] | .[]
' "$FEATURE_FILE" 2>/dev/null || true)

if [[ -z "$DEPENDENTS" ]]; then
  exit 0
fi

acquire_lock
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TEMP_FILE=$(mktemp)

# Batch block all dependents in a single jq call
DEP_JSON=$(echo "$DEPENDENTS" | jq -R . | jq -s .)
jq --argjson ids "$DEP_JSON" --arg ts "$TIMESTAMP" --arg fid "$FAILED_ID" '
  .features |= map(
    if (.id as $id | $ids | index($id)) then
      .status = "blocked" | .notes = "Blocked: dependency \($fid) failed" | .blocked_at = $ts
    else . end
  ) | .updated_at = $ts
' "$FEATURE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$FEATURE_FILE"

for DEP_ID in $DEPENDENTS; do
  echo "🚫 $DEP_ID blocked (depends on failed $FAILED_ID)"
done
