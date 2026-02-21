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
CONFIG_FILE=".autonomy/config.json"
COMPACT_SCRIPT="$PLUGIN_ROOT/scripts/compact-context.sh"
LOAD_ROLE_SCRIPT="$PLUGIN_ROOT/scripts/load-role.sh"
NOTIFY_SCRIPT="$PLUGIN_ROOT/scripts/notify.sh"

# Check if autonomous loop is active
if [[ ! -f "$LOOP_STATE" ]]; then
  exit 0
fi

# Send notification helper
send_notify() {
  local event="$1" message="$2"
  if [[ -x "$NOTIFY_SCRIPT" ]]; then
    "$NOTIFY_SCRIPT" "$event" "$message" 2>/dev/null || true
  fi
}

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

# Propagate failures to dependents and notify
FAILED_IDS=$(jq -r '[.features[] | select(.status == "failed") | .id] | .[]' "$FEATURE_FILE" 2>/dev/null || true)
for FID in $FAILED_IDS; do
  "$PLUGIN_ROOT/scripts/propagate-failure.sh" "$FID" 2>/dev/null || true
done
# Notify for newly failed tasks (no completed_at means just failed in this cycle)
for FID in $FAILED_IDS; do
  COMPLETED_AT=$(jq -r --arg id "$FID" '.features[] | select(.id == $id) | .completed_at // ""' "$FEATURE_FILE" 2>/dev/null || echo "")
  if [[ -z "$COMPLETED_AT" || "$COMPLETED_AT" == "null" ]]; then
    FTITLE=$(jq -r --arg id "$FID" '.features[] | select(.id == $id) | .title' "$FEATURE_FILE" 2>/dev/null || echo "")
    send_notify "task_failed" "任务 $FID ($FTITLE) 失败"
    # Mark completed_at to avoid re-notifying
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    TEMP_FILE=$(mktemp)
    jq --arg id "$FID" --arg ts "$TIMESTAMP" '
      .features |= map(if .id == $id then .completed_at = $ts else . end)
    ' "$FEATURE_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$FEATURE_FILE"
  fi
done

# Check for remaining tasks
PENDING=$(jq '[.features[] | select(.status == "pending" or .status == "in_progress")] | length' "$FEATURE_FILE")
if [[ $PENDING -eq 0 ]]; then
  echo "✅ All tasks completed! Autonomous loop finished."
  "$PLUGIN_ROOT/scripts/summary.sh" "$FEATURE_FILE" 2>/dev/null || true
  send_notify "all_done" "所有任务已完成！"
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
CURRENT_TITLE=$(echo "$NEXT_TASK" | jq -r '.title')
CURRENT_ROLE=$(echo "$NEXT_TASK" | jq -r '.role // "developer"')

# Timeout check for in_progress tasks
if [[ "$CURRENT_STATUS" == "in_progress" ]]; then
  TASK_TIMEOUT=30
  if [[ -f "$CONFIG_FILE" ]]; then
    TASK_TIMEOUT=$(jq -r '.task_timeout_minutes // 30' "$CONFIG_FILE")
  fi
  ASSIGNED_AT=$(echo "$NEXT_TASK" | jq -r '.assigned_at // ""')
  if [[ -n "$ASSIGNED_AT" && "$ASSIGNED_AT" != "null" ]]; then
    if date --version &>/dev/null 2>&1; then
      ASSIGNED_EPOCH=$(date -d "$ASSIGNED_AT" +%s 2>/dev/null || echo 0)
    else
      ASSIGNED_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$ASSIGNED_AT" +%s 2>/dev/null || echo 0)
    fi
    NOW_EPOCH=$(date +%s)
    ELAPSED_MIN=$(( (NOW_EPOCH - ASSIGNED_EPOCH) / 60 ))
    if [[ $ASSIGNED_EPOCH -gt 0 && $ELAPSED_MIN -ge $TASK_TIMEOUT ]]; then
      echo "⏰ Task $CURRENT_ID timed out after ${ELAPSED_MIN}m (limit: ${TASK_TIMEOUT}m). Marking as failed."
      acquire_lock
      TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      TEMP_FILE=$(mktemp)
      jq --arg id "$CURRENT_ID" --arg ts "$TIMESTAMP" '
        .features |= map(if .id == $id then .status = "failed" | .notes = "Timed out" | .completed_at = $ts else . end) |
        .updated_at = $ts
      ' "$FEATURE_FILE" > "$TEMP_FILE"
      mv "$TEMP_FILE" "$FEATURE_FILE"
      "$PLUGIN_ROOT/scripts/propagate-failure.sh" "$CURRENT_ID" 2>/dev/null || true
      send_notify "task_timeout" "任务 $CURRENT_ID ($CURRENT_TITLE) 超时 (${ELAPSED_MIN}分钟)"
      # Re-check for next task after timeout handling
      NEXT_TASK=$("$PLUGIN_ROOT/scripts/get-next-task-json.sh" "$FEATURE_FILE" 2>/dev/null || true)
      if [[ -z "$NEXT_TASK" || "$NEXT_TASK" == "null" ]]; then
        echo "🚫 No eligible tasks after timeout handling. Stopping."
        rm "$LOOP_STATE"
        exit 0
      fi
      CURRENT_ID=$(echo "$NEXT_TASK" | jq -r '.id')
      CURRENT_STATUS=$(echo "$NEXT_TASK" | jq -r '.status')
      CURRENT_TITLE=$(echo "$NEXT_TASK" | jq -r '.title')
      CURRENT_ROLE=$(echo "$NEXT_TASK" | jq -r '.role // "developer"')
    fi
  fi
fi

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

# Rotate progress.txt if needed
if [[ -x "$PLUGIN_ROOT/scripts/rotate-progress.sh" ]]; then
  "$PLUGIN_ROOT/scripts/rotate-progress.sh" 2>/dev/null || true
fi

# Generate compact context (file only, not inlined into prompt)
if [[ -x "$COMPACT_SCRIPT" ]]; then
  "$COMPACT_SCRIPT" "$FEATURE_FILE" "$PROGRESS_FILE" 2>/dev/null || true
fi

# Load role prompt
ROLE_PROMPT="You are an autonomous shift worker. Follow the Autonomy Protocol strictly."
if [[ -x "$LOAD_ROLE_SCRIPT" ]]; then
  ROLE_PROMPT=$("$LOAD_ROLE_SCRIPT" "$CURRENT_ROLE" 2>/dev/null || echo "$ROLE_PROMPT")
fi

# Update iteration
NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${LOOP_STATE}.tmp.$$"
sed "s/^iteration:[[:space:]].*/iteration: $NEXT_ITERATION/" "$LOOP_STATE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$LOOP_STATE"

# Build the prompt for the next iteration
# NOTE: Do NOT inline compact context or task details into the prompt.
# These may contain special characters that break shell heredoc or jq parsing.
# Instead, instruct Claude to read the files directly.
PROMPT="$ROLE_PROMPT

## Current Task
Task $CURRENT_ID [$CURRENT_ROLE]: $CURRENT_TITLE
${GIT_WARNING:+
## Git Status Warning
$GIT_WARNING
}
## Instructions
1. Read .autonomy/context.compact.json (if it exists) — it contains your current task details, dependency info, queue summary, and relevant progress
2. Read .autonomy/config.json for project settings
3. If compact context is not available, read .autonomy/feature_list.json and .autonomy/progress.txt instead
4. Execute the current task, following all acceptance_criteria
5. Verify your work (run tests/lint if configured)
6. Update feature_list.json: set status to \"done\", set completed_at
7. Append completion summary to progress.txt
8. Git commit with format: feat({task_id}): {title}

If the task fails, increment attempt_count. If attempt_count >= max_attempts, set status to \"failed\".
If blocked by dependencies, set status to \"blocked\" and record the blocker.

CRITICAL: After finishing this task, you MUST exit the conversation. Do NOT wait or ask for confirmation. Just exit. The loop will automatically assign the next task."

SYSTEM_MSG="🔄 Autonomy iteration $NEXT_ITERATION | Task: $CURRENT_ID [$CURRENT_ROLE] | /autocc:stop to cancel"

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
