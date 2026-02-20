#!/usr/bin/env bash

# Autonomy Stop Hook
# When autonomous loop is active, intercepts exit and feeds the next task as a new prompt.
# Unlike ralph-wiggum which repeats the same prompt, this reads the next task from feature_list.json.

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PLUGIN_ROOT/scripts/lock-utils.sh"

LOOP_STATE=".claude/autonomy-loop.local.md"
FEATURE_FILE=".autonomy/feature_list.json"
PROGRESS_FILE=".autonomy/progress.txt"

# Check if autonomous loop is active
if [[ ! -f "$LOOP_STATE" ]]; then
  exit 0
fi

# Parse frontmatter — extract value for a given key
parse_frontmatter_value() {
  local file="$1" key="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep -m1 "^${key}:" | sed "s/^${key}:[[:space:]]*//" | sed 's/^"//;s/"$//' | tr -d '[:space:]'
}

ACTIVE=$(parse_frontmatter_value "$LOOP_STATE" "active")
ITERATION=$(parse_frontmatter_value "$LOOP_STATE" "iteration")
MAX_ITERATIONS=$(parse_frontmatter_value "$LOOP_STATE" "max_iterations")

if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Autonomy loop: State file corrupted (iteration: '$ITERATION'). Stopping." >&2
  rm "$LOOP_STATE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Autonomy loop: State file corrupted (max_iterations: '$MAX_ITERATIONS'). Stopping." >&2
  rm "$LOOP_STATE"
  exit 0
fi

# Check max iterations
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 Autonomy loop: Max iterations ($MAX_ITERATIONS) reached."
  rm "$LOOP_STATE"
  exit 0
fi

# Check if feature_list.json exists
if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "⚠️  Autonomy loop: feature_list.json not found. Stopping." >&2
  rm "$LOOP_STATE"
  exit 0
fi

# Propagate failures to dependents
FAILED_IDS=$(jq -r '[.features[] | select(.status == "failed") | .id] | .[]' "$FEATURE_FILE" 2>/dev/null || true)
for FID in $FAILED_IDS; do
  "$PLUGIN_ROOT/scripts/propagate-failure.sh" "$FID" 2>/dev/null || true
done

# Check for remaining tasks
PENDING=$(jq '[.features[] | select(.status == "pending" or .status == "in_progress")] | length' "$FEATURE_FILE")
if [[ $PENDING -eq 0 ]]; then
  echo "✅ All tasks completed! Autonomous loop finished."
  "$PLUGIN_ROOT/scripts/summary.sh" "$FEATURE_FILE" 2>/dev/null || true
  rm "$LOOP_STATE"
  exit 0
fi

# Find next task to work on (using shared script)
NEXT_TASK=$("$PLUGIN_ROOT/scripts/get-next-task-json.sh" "$FEATURE_FILE" 2>/dev/null || true)

if [[ -z "$NEXT_TASK" || "$NEXT_TASK" == "null" ]]; then
  echo "🚫 No eligible tasks (remaining tasks are blocked). Stopping."
  "$PLUGIN_ROOT/scripts/check-cycles.sh" "$FEATURE_FILE" 2>&1 || true
  rm "$LOOP_STATE"
  exit 0
fi

CURRENT_ID=$(echo "$NEXT_TASK" | jq -r '.id')
CURRENT_STATUS=$(echo "$NEXT_TASK" | jq -r '.status')

# Check for uncommitted changes from possibly interrupted session
GIT_WARNING=""
if [[ "$CURRENT_STATUS" == "in_progress" ]] && command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
  DIRTY=$(git status --porcelain 2>/dev/null || true)
  if [[ -n "$DIRTY" ]]; then
    GIT_WARNING="WARNING: Uncommitted changes detected from a possibly interrupted session. Review git status before continuing. Consider stashing or reverting if the changes are incomplete."
  fi
fi

# Mark as in_progress if pending
if [[ "$CURRENT_STATUS" != "in_progress" ]]; then
  acquire_lock
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  TEMP_FILE=$(mktemp)
  jq --arg id "$CURRENT_ID" --arg ts "$TIMESTAMP" '
    .features |= map(if .id == $id then .status = "in_progress" | .assigned_at = $ts else . end) |
    .updated_at = $ts
  ' "$FEATURE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$FEATURE_FILE"
fi

# Get task details
TASK_DETAIL=$(jq -r --arg id "$CURRENT_ID" '
  .features[] | select(.id == $id) |
  "Task \(.id): \(.title)\nDescription: \(.description)\nAcceptance Criteria: \(.acceptance_criteria | join("; "))\nAttempt: \(.attempt_count + 1)/\(.max_attempts)"
' "$FEATURE_FILE")

# Rotate progress.txt if needed
if [[ -x "$PLUGIN_ROOT/scripts/rotate-progress.sh" ]]; then
  "$PLUGIN_ROOT/scripts/rotate-progress.sh" 2>/dev/null || true
fi

# Get recent progress for context
RECENT_PROGRESS=""
if [[ -f "$PROGRESS_FILE" ]]; then
  RECENT_PROGRESS=$(tail -20 "$PROGRESS_FILE")
fi

# Update iteration
NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${LOOP_STATE}.tmp.$$"
sed "s/^iteration:[[:space:]].*/iteration: $NEXT_ITERATION/" "$LOOP_STATE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$LOOP_STATE"

# Build the prompt for the next iteration
PROMPT=$(cat <<PROMPT_EOF
You are an autonomous shift worker. Follow the Autonomy Protocol strictly.

## Current Task
$TASK_DETAIL

## Recent Progress
$RECENT_PROGRESS

${GIT_WARNING:+## Git Status Warning
$GIT_WARNING

}## Instructions
1. Read .autonomy/progress.txt for full context
2. Read .autonomy/feature_list.json for task details
3. Read .autonomy/config.json for project settings
4. Execute the task above, following all acceptance_criteria
5. Verify your work (run tests/lint if configured)
6. Update feature_list.json: set status to "done", set completed_at
7. Append completion summary to progress.txt
8. Git commit with format: feat({task_id}): {title}

If the task fails, increment attempt_count. If attempt_count >= max_attempts, set status to "failed".
If blocked by dependencies, set status to "blocked" and record the blocker.

After finishing this task, exit normally. The loop will automatically assign the next task.
PROMPT_EOF
)

SYSTEM_MSG="🔄 Autonomy iteration $NEXT_ITERATION | Task: $CURRENT_ID | /autocc:stop to cancel"

# Output JSON to block the stop and feed next task prompt
jq -n \
  --arg prompt "$PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
