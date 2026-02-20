#!/usr/bin/env bash
# Print a completion summary of all tasks.
set -euo pipefail

FEATURE_FILE="${1:-.autonomy/feature_list.json}"

if [[ ! -f "$FEATURE_FILE" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

TOTAL=$(jq '.features | length' "$FEATURE_FILE")
DONE=$(jq '[.features[] | select(.status == "done")] | length' "$FEATURE_FILE")
FAILED=$(jq '[.features[] | select(.status == "failed")] | length' "$FEATURE_FILE")
BLOCKED=$(jq '[.features[] | select(.status == "blocked")] | length' "$FEATURE_FILE")

echo ""
echo "═══════════════════════════════════════"
echo "📊 Autonomy Run Summary"
echo "═══════════════════════════════════════"
echo "  Total:   $TOTAL"
echo "  Done:    $DONE ✅"
echo "  Failed:  $FAILED ❌"
echo "  Blocked: $BLOCKED 🚫"
echo ""

# List completed tasks
if [[ $DONE -gt 0 ]]; then
  echo "Completed:"
  jq -r '.features[] | select(.status == "done") | "  ✅ \(.id) - \(.title)"' "$FEATURE_FILE"
fi

# List failed tasks
if [[ $FAILED -gt 0 ]]; then
  echo "Failed:"
  jq -r '.features[] | select(.status == "failed") | "  ❌ \(.id) - \(.title) (attempts: \(.attempt_count)/\(.max_attempts))"' "$FEATURE_FILE"
fi

# List blocked tasks
if [[ $BLOCKED -gt 0 ]]; then
  echo "Blocked:"
  jq -r '.features[] | select(.status == "blocked") | "  🚫 \(.id) - \(.title) — \(.notes // "no reason")"' "$FEATURE_FILE"
fi

echo "═══════════════════════════════════════"
