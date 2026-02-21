#!/usr/bin/env bash
set -euo pipefail

AUTONOMY_DIR=".autonomy"
FEATURE_FILE="$AUTONOMY_DIR/feature_list.json"

# --- Helpers ---
usage() {
  echo "Usage: reset-autonomy.sh [--hard] [--force]"
  echo ""
  echo "Options:"
  echo "  --hard   Clear ALL tasks (default: keep pending tasks)"
  echo "  --force  Skip confirmation prompt"
  exit 0
}

die() { echo "❌ $1" >&2; exit 1; }

# --- Parse args ---
HARD=false
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --hard)  HARD=true ;;
    --force) FORCE=true ;;
    --help|-h) usage ;;
    *) die "Unknown option: $arg" ;;
  esac
done

# --- Preconditions ---
[[ -f "$FEATURE_FILE" ]] || die "Autonomy system not initialized. Run /autocc:init first."
command -v jq &>/dev/null || die "jq is required. Install with: brew install jq"

# --- Gather stats ---
TOTAL=$(jq '.features | length' "$FEATURE_FILE")
PENDING=$(jq '[.features[] | select(.status == "pending")] | length' "$FEATURE_FILE")
IN_PROGRESS=$(jq '[.features[] | select(.status == "in_progress")] | length' "$FEATURE_FILE")
DONE=$(jq '[.features[] | select(.status == "done")] | length' "$FEATURE_FILE")
FAILED=$(jq '[.features[] | select(.status == "failed")] | length' "$FEATURE_FILE")
BLOCKED=$(jq '[.features[] | select(.status == "blocked")] | length' "$FEATURE_FILE")

# --- Show summary ---
if [[ "$HARD" == true ]]; then
  echo "🔴 Hard Reset — will clear ALL $TOTAL tasks"
else
  REMOVE_COUNT=$((DONE + FAILED + BLOCKED))
  echo "🟡 Soft Reset — will remove $REMOVE_COUNT tasks (done=$DONE, failed=$FAILED, blocked=$BLOCKED), keep $PENDING pending"
fi

if [[ $IN_PROGRESS -gt 0 ]]; then
  echo "⚠️  $IN_PROGRESS task(s) currently in_progress — will be reset to pending (soft) or removed (hard)"
fi

echo ""
echo "Will also clean up: progress.txt, progress.archive.txt, context.compact.json, .lock, autonomy-loop.local.md"

# --- Confirm ---
if [[ "$FORCE" != true ]]; then
  echo ""
  read -r -p "Proceed? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo ""

# --- Reset feature_list.json ---
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ "$HARD" == true ]]; then
  # Hard: clear all tasks
  jq --arg ts "$TIMESTAMP" '.features = [] | .updated_at = $ts' "$FEATURE_FILE" > "$FEATURE_FILE.tmp" \
    && mv "$FEATURE_FILE.tmp" "$FEATURE_FILE"
  echo "✅ Cleared all tasks"
else
  # Soft: keep only pending, reset in_progress to pending
  jq --arg ts "$TIMESTAMP" '
    .features = [.features[] | select(.status == "pending" or .status == "in_progress") | .status = "pending" | .attempts = 0]
    | .updated_at = $ts
  ' "$FEATURE_FILE" > "$FEATURE_FILE.tmp" \
    && mv "$FEATURE_FILE.tmp" "$FEATURE_FILE"
  KEPT=$(jq '.features | length' "$FEATURE_FILE")
  echo "✅ Kept $KEPT pending tasks, removed completed/failed/blocked"
fi

# --- Reset progress.txt ---
PROJECT=$(jq -r '.project' "$FEATURE_FILE")
cat > "$AUTONOMY_DIR/progress.txt" <<EOF
=== Autonomy System Reset | $TIMESTAMP ===
Project: $PROJECT
Status: RESET
Notes: System reset. Ready for new development cycle.
===
EOF
echo "✅ Reset progress.txt"

# --- Remove auxiliary files ---
for f in "$AUTONOMY_DIR/progress.archive.txt" "$AUTONOMY_DIR/context.compact.json" "$AUTONOMY_DIR/.lock"; do
  if [[ -f "$f" ]]; then
    rm "$f"
    echo "✅ Removed $f"
  fi
done

if [[ -f ".claude/autonomy-loop.local.md" ]]; then
  rm ".claude/autonomy-loop.local.md"
  echo "✅ Removed .claude/autonomy-loop.local.md"
fi

echo ""
echo "🎉 Reset complete. Use /autocc:status to verify, then /autocc:add or /autocc:plan to start a new cycle."
