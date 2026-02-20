#!/usr/bin/env bash
# Rotate progress.txt when it exceeds max_lines.
# Moves excess content to progress.archive.txt, keeps only the most recent entries.

set -euo pipefail

PROGRESS_FILE=".autonomy/progress.txt"
ARCHIVE_FILE=".autonomy/progress.archive.txt"
CONFIG_FILE=".autonomy/config.json"
DEFAULT_MAX_LINES=100

if [[ ! -f "$PROGRESS_FILE" ]]; then
  exit 0
fi

# Read max_lines from config, fallback to default
MAX_LINES=$DEFAULT_MAX_LINES
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
  CONFIGURED=$(jq -r '.progress_max_lines // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [[ -n "$CONFIGURED" && "$CONFIGURED" =~ ^[0-9]+$ ]]; then
    MAX_LINES=$CONFIGURED
  fi
fi

TOTAL_LINES=$(wc -l < "$PROGRESS_FILE" | tr -d ' ')

if [[ $TOTAL_LINES -le $MAX_LINES ]]; then
  exit 0
fi

# Calculate how many lines to archive
KEEP_LINES=$MAX_LINES
ARCHIVE_LINES=$((TOTAL_LINES - KEEP_LINES))

# Append old content to archive
head -n "$ARCHIVE_LINES" "$PROGRESS_FILE" >> "$ARCHIVE_FILE"

# Keep only recent content
TEMP_FILE=$(mktemp)
tail -n "$KEEP_LINES" "$PROGRESS_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$PROGRESS_FILE"

echo "📦 Progress rotated: archived $ARCHIVE_LINES lines, kept $KEEP_LINES lines."
