#!/usr/bin/env bash
set -euo pipefail

LOOP_STATE=".claude/autonomy-loop.local.md"

if [[ ! -f "$LOOP_STATE" ]]; then
  echo "ℹ️  No active autonomous loop."
  exit 0
fi

rm "$LOOP_STATE"
echo "🛑 Autonomous loop stopped."
echo "   Use /autocc:status to see current progress."
echo "   Use /autocc:run to restart."
