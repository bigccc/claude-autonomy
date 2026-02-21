#!/usr/bin/env bash
# claude-autonomy 卸载脚本 (macOS)
# 移除命令、注销 Stop Hook

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands/autocc"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "🗑  claude-autonomy 卸载脚本"
echo "═══════════════════════════════════════"

# 1. 移除命令文件
if [[ -d "$COMMANDS_DIR" ]]; then
  rm -rf "$COMMANDS_DIR"
  echo "✅ 已移除命令目录: $COMMANDS_DIR"
else
  echo "ℹ️  命令目录不存在，跳过"
fi

# 2. 注销 Stop Hook
if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
  HOOK_CMD="$PLUGIN_ROOT/hooks/stop-hook.sh"
  HAS_HOOK=$(jq -r '
    .hooks.Stop // [] | .[] | .hooks // [] | .[] |
    select(.command == "'"$HOOK_CMD"'") | .command
  ' "$SETTINGS_FILE" 2>/dev/null || true)

  if [[ -n "$HAS_HOOK" ]]; then
    TEMP_FILE=$(mktemp)
    jq --arg cmd "$HOOK_CMD" '
      .hooks.Stop //= [] |
      .hooks.Stop = [
        .hooks.Stop[] |
        .hooks = [.hooks[] | select(.command != $cmd)] |
        select(.hooks | length > 0)
      ] |
      if .hooks.Stop == [] then del(.hooks.Stop) else . end |
      if .hooks == {} then del(.hooks) else . end
    ' "$SETTINGS_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$SETTINGS_FILE"
    echo "✅ 已注销 Stop Hook"
  else
    echo "ℹ️  Stop Hook 未注册，跳过"
  fi
else
  echo "ℹ️  settings.json 不存在或 jq 未安装，跳过 Hook 清理"
fi

echo ""
echo "═══════════════════════════════════════"
echo "✅ 卸载完成！"
echo ""
echo "注意: 项目中的 .autonomy/ 目录和 CLAUDE.md 中的 Autonomy Protocol 未被删除。"
echo "如需完全清理，请手动删除项目中的 .autonomy/ 目录。"
