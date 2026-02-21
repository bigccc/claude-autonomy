#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-$(basename "$(pwd)")}"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTONOMY_DIR=".autonomy"

# Guard: already initialized
if [[ -d "$AUTONOMY_DIR" ]]; then
  echo "⚠️  Autonomy system already initialized in this project."
  echo "   Use /autocc:status to view current state."
  echo "   Delete .autonomy/ to re-initialize."
  exit 0
fi

# Create structure
mkdir -p "$AUTONOMY_DIR"

# Generate feature_list.json from template
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if ! command -v jq &>/dev/null; then
  echo "❌ jq is required. Install with: brew install jq" >&2
  exit 1
fi
jq --arg proj "$PROJECT_NAME" --arg ts "$TIMESTAMP" \
  '.project = $proj | .created_at = $ts | .updated_at = $ts' \
  "$PLUGIN_ROOT/templates/feature_list.template.json" > "$AUTONOMY_DIR/feature_list.json"

# Initialize progress.txt
cat > "$AUTONOMY_DIR/progress.txt" <<EOF
=== Autonomy System Initialized | $TIMESTAMP ===
Project: $PROJECT_NAME
Status: INITIALIZED
Notes: System ready. Add tasks with /autocc:add, then run with /autocc:run or /autocc:next.
===
EOF

# Create config.json
cat > "$AUTONOMY_DIR/config.json" <<EOF
{
  "max_attempts_per_task": 3,
  "auto_commit": true,
  "verify_before_done": true,
  "commit_prefix": "feat",
  "test_command": "",
  "lint_command": "",
  "progress_max_lines": 100,
  "task_timeout_minutes": 30,
  "notify_webhook": "",
  "notify_type": "feishu"
}
EOF

# Append autonomy protocol to CLAUDE.md
if [[ -f "CLAUDE.md" ]]; then
  if grep -q "# Autonomy Protocol" "CLAUDE.md"; then
    echo "ℹ️  CLAUDE.md already contains Autonomy Protocol, skipping."
  else
    echo "" >> "CLAUDE.md"
    cat "$PLUGIN_ROOT/templates/CLAUDE.autonomy.md" >> "CLAUDE.md"
    echo "✅ Appended Autonomy Protocol to existing CLAUDE.md"
  fi
else
  cp "$PLUGIN_ROOT/templates/CLAUDE.autonomy.md" "CLAUDE.md"
  echo "✅ Created CLAUDE.md with Autonomy Protocol"
fi

# Add runtime files to .gitignore
if [[ -f ".gitignore" ]]; then
  for pattern in ".claude/autonomy-loop.local.md" ".autonomy/loop-state.json" ".autonomy/progress.archive.txt" ".autonomy/.lock"; do
    if ! grep -qF "$pattern" ".gitignore"; then
      echo "$pattern" >> ".gitignore"
    fi
  done
else
  cat > ".gitignore" <<EOF
.claude/autonomy-loop.local.md
.autonomy/loop-state.json
.autonomy/progress.archive.txt
.autonomy/.lock
EOF
fi

echo ""
echo "✅ Autonomy system initialized for project: $PROJECT_NAME"
echo ""
echo "Structure created:"
echo "  .autonomy/"
echo "  ├── feature_list.json   — Task queue"
echo "  ├── progress.txt        — Handoff log between sessions"
echo "  └── config.json         — Project settings"
echo ""
echo "Next steps:"
echo "  /autocc:add \"Task title\" \"Task description\"  — Add a task"
echo "  /autocc:status                                  — View current state"
echo "  /autocc:next                                    — Execute next task"
echo "  /autocc:run                                     — Start autonomous loop"
