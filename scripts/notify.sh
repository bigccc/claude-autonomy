#!/usr/bin/env bash
# Notification script for autonomy system
# Sends webhook notifications to Feishu/DingTalk/WeCom/ServerChan
#
# Usage: notify.sh <event_type> <message>
#   event_type: task_done | task_failed | all_done | task_timeout
#   message: notification content

set -euo pipefail

EVENT_TYPE="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$EVENT_TYPE" || -z "$MESSAGE" ]]; then
  echo "Usage: notify.sh <event_type> <message>" >&2
  exit 1
fi

CONFIG_FILE=".autonomy/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  # Try relative to script location
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  CONFIG_FILE="$PROJECT_ROOT/.autonomy/config.json"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    exit 0
  fi
fi

if ! command -v jq &>/dev/null; then
  echo "⚠️  jq not found, skipping notification." >&2
  exit 0
fi

WEBHOOK=$(jq -r '.notify_webhook // ""' "$CONFIG_FILE")
NOTIFY_TYPE=$(jq -r '.notify_type // "feishu"' "$CONFIG_FILE")

# No webhook configured — silently skip
if [[ -z "$WEBHOOK" ]]; then
  exit 0
fi

# Prefix with event type emoji
case "$EVENT_TYPE" in
  task_done)    PREFIX="✅ 任务完成" ;;
  task_failed)  PREFIX="❌ 任务失败" ;;
  all_done)     PREFIX="🎉 全部完成" ;;
  task_timeout) PREFIX="⏰ 任务超时" ;;
  *)            PREFIX="📢 通知" ;;
esac

FULL_MESSAGE="[$PREFIX] $MESSAGE"

# Build JSON payload based on notify_type
case "$NOTIFY_TYPE" in
  feishu)
    PAYLOAD=$(jq -n --arg text "$FULL_MESSAGE" '{msg_type:"text",content:{text:$text}}')
    ;;
  dingtalk)
    PAYLOAD=$(jq -n --arg text "$FULL_MESSAGE" '{msgtype:"text",text:{content:$text}}')
    ;;
  wecom)
    PAYLOAD=$(jq -n --arg text "$FULL_MESSAGE" '{msgtype:"text",text:{content:$text}}')
    ;;
  serverchan)
    # ServerChan uses notify_webhook as the SendKey
    SENDKEY="$WEBHOOK"
    if [[ "$SENDKEY" =~ ^sctp([0-9]+)t ]]; then
      SC_NUM="${BASH_REMATCH[1]}"
      SC_URL="https://${SC_NUM}.push.ft07.com/send/${SENDKEY}.send"
    else
      SC_URL="https://sctapi.ftqq.com/${SENDKEY}.send"
    fi
    SC_TITLE="$PREFIX"
    SC_DESP="$MESSAGE"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "text=${SC_TITLE}&desp=${SC_DESP}" \
      --connect-timeout 5 \
      --max-time 10 \
      "$SC_URL" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
      echo "📨 Notification sent (serverchan): $EVENT_TYPE"
    else
      echo "⚠️  Notification failed (HTTP $HTTP_CODE)" >&2
    fi
    exit 0
    ;;
  *)
    echo "⚠️  Unknown notify_type: $NOTIFY_TYPE" >&2
    exit 1
    ;;
esac

# Send webhook request (timeout 10s, silent on failure)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --connect-timeout 5 \
  --max-time 10 \
  "$WEBHOOK" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "📨 Notification sent ($NOTIFY_TYPE): $EVENT_TYPE"
else
  echo "⚠️  Notification failed (HTTP $HTTP_CODE)" >&2
fi

exit 0
