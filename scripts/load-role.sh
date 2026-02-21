#!/usr/bin/env bash
# Load an agent role prompt template.
# Usage: load-role.sh <role_name>
# Output: role prompt text to stdout
# Falls back to developer role if the specified role is not found.

set -euo pipefail

ROLE="${1:-developer}"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$PLUGIN_ROOT/templates/agents"

ROLE_FILE="$AGENTS_DIR/${ROLE}.md"

if [[ ! -f "$ROLE_FILE" ]]; then
  # Fallback to developer
  ROLE_FILE="$AGENTS_DIR/developer.md"
fi

if [[ -f "$ROLE_FILE" ]]; then
  cat "$ROLE_FILE"
else
  # Ultimate fallback — no role file exists at all
  echo "You are an autonomous shift worker. Follow the Autonomy Protocol strictly."
fi
