#!/usr/bin/env bash
# File locking utility using mkdir (atomic, portable).
# Usage:
#   source lock-utils.sh
#   acquire_lock   # blocks until lock acquired
#   ... do work ...
#   release_lock

set -euo pipefail

LOCK_DIR=".autonomy/.lock"
LOCK_TIMEOUT=10

acquire_lock() {
  local waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    # Check for stale lock (older than 60s)
    if [[ -d "$LOCK_DIR" ]]; then
      local lock_age
      if [[ "$(uname)" == "Darwin" ]]; then
        lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR") ))
      else
        lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR") ))
      fi
      if [[ $lock_age -gt 60 ]]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
        continue
      fi
    fi
    sleep 0.1
    waited=$((waited + 1))
    if [[ $waited -ge $((LOCK_TIMEOUT * 10)) ]]; then
      echo "⚠️  Lock timeout after ${LOCK_TIMEOUT}s" >&2
      return 1
    fi
  done
  trap release_lock EXIT
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
  trap - EXIT
}
