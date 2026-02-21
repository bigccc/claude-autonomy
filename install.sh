#!/usr/bin/env bash
# claude-autonomy 一键安装脚本 (macOS)
# 安装命令、注册 Stop Hook、设置脚本权限

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands/autocc"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "🔧 claude-autonomy 安装脚本"
echo "═══════════════════════════════════════"
echo "插件目录: $PLUGIN_ROOT"
echo ""

# 检查依赖
if ! command -v jq &>/dev/null; then
  echo "❌ 需要 jq，请先安装: brew install jq"
  exit 1
fi

# 1. 确保目录存在
mkdir -p "$COMMANDS_DIR"

# 2. 安装命令文件（替换 CLAUDE_PLUGIN_ROOT 为实际路径）
echo "📦 安装命令..."
for f in "$PLUGIN_ROOT"/commands/*.md; do
  BASENAME="$(basename "$f")"
  sed "s|\${CLAUDE_PLUGIN_ROOT}|$PLUGIN_ROOT|g" "$f" > "$COMMANDS_DIR/$BASENAME"
  echo "   ✅ /autocc:${BASENAME%.md}"
done

# 3. 设置脚本可执行权限
echo ""
echo "🔑 设置脚本权限..."
chmod +x "$PLUGIN_ROOT"/scripts/*.sh
chmod +x "$PLUGIN_ROOT"/hooks/*.sh
echo "   ✅ scripts/*.sh, hooks/*.sh"

# 4. 注册 Stop Hook 到 settings.json
echo ""
echo "🪝 注册 Stop Hook..."

HOOK_CMD="$PLUGIN_ROOT/hooks/stop-hook.sh"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  # settings.json 不存在，创建一个
  echo '{}' > "$SETTINGS_FILE"
fi

# 检查是否已注册
EXISTING_HOOK=$(jq -r '
  .hooks.Stop // [] | .[] | .hooks // [] | .[] |
  select(.command == "'"$HOOK_CMD"'") | .command
' "$SETTINGS_FILE" 2>/dev/null || true)

if [[ -n "$EXISTING_HOOK" ]]; then
  echo "   ℹ️  Stop Hook 已注册，跳过"
else
  # 添加 Stop Hook
  TEMP_FILE=$(mktemp)
  jq --arg cmd "$HOOK_CMD" '
    .hooks //= {} |
    .hooks.Stop //= [] |
    .hooks.Stop += [{
      "hooks": [{
        "type": "command",
        "command": $cmd
      }]
    }]
  ' "$SETTINGS_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$SETTINGS_FILE"
  echo "   ✅ Stop Hook 已注册到 ~/.claude/settings.json"
fi

echo ""
echo "═══════════════════════════════════════"
echo "✅ 安装完成！"
echo ""
echo "使用方法:"
echo "  1. 重启 Claude Code（如果正在运行）"
echo "  2. 在项目目录中运行 /autocc:init"
echo "  3. 使用 /autocc:plan 或 /autocc:add 添加任务"
echo "  4. 使用 /autocc:run 启动自主循环"
echo ""
echo "卸载: bash $PLUGIN_ROOT/uninstall.sh"
