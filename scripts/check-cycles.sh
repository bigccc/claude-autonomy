#!/usr/bin/env bash
# Detect circular dependencies in the task graph.
# Outputs cycle info to stderr, exits 0 if no cycles, 1 if cycles found.
set -euo pipefail

FEATURE_FILE="${1:-.autonomy/feature_list.json}"

if [[ ! -f "$FEATURE_FILE" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

# Extract non-done tasks with dependencies as "id:dep1,dep2" lines
GRAPH=$(jq -r '
  [.features[] | select(.status != "done" and .status != "failed")] |
  map(select(.dependencies | length > 0) | "\(.id):\(.dependencies | join(","))") | .[]
' "$FEATURE_FILE" 2>/dev/null || true)

if [[ -z "$GRAPH" ]]; then
  exit 0
fi

# Simple cycle detection: for each task, follow deps up to depth N
# If we revisit a node, there's a cycle.
declare -A DEPS
while IFS= read -r line; do
  id="${line%%:*}"
  deps="${line#*:}"
  DEPS["$id"]="$deps"
done <<< "$GRAPH"

check_cycle() {
  local start="$1" current="$2" visited="$3"
  local dep_str="${DEPS[$current]:-}"
  [[ -z "$dep_str" ]] && return 1

  IFS=',' read -ra dep_list <<< "$dep_str"
  for dep in "${dep_list[@]}"; do
    if [[ "$dep" == "$start" ]]; then
      echo "🔄 循环依赖: $visited -> $dep" >&2
      return 0
    fi
    if [[ "$visited" == *"$dep"* ]]; then
      continue
    fi
    if check_cycle "$start" "$dep" "$visited -> $dep"; then
      return 0
    fi
  done
  return 1
}

FOUND=0
for id in "${!DEPS[@]}"; do
  if check_cycle "$id" "$id" "$id"; then
    FOUND=1
  fi
done

exit $((1 - FOUND))
