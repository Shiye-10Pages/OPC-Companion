#!/bin/bash
# 安装 / 卸载每日巡检 launchd agent。
# 用法：
#   ./scripts/install-daily-inspect.sh           # 安装
#   ./scripts/install-daily-inspect.sh --uninstall
#   ./scripts/install-daily-inspect.sh --run-now  # 立即手动跑一次验证

set -euo pipefail

LABEL="com.opc.companion.daily-inspect"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$REPO_DIR/scripts/daily-inspect.sh"
PLIST_TEMPLATE="$REPO_DIR/scripts/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

case "${1:-}" in
    --uninstall)
        launchctl unload "$PLIST_DST" 2>/dev/null || true
        rm -f "$PLIST_DST"
        echo "已卸载 $LABEL"
        exit 0
        ;;
    --run-now)
        exec "$SCRIPT_PATH"
        ;;
esac

if [ ! -f "$PLIST_TEMPLATE" ]; then
    echo "找不到 plist 模板：$PLIST_TEMPLATE" >&2
    exit 1
fi
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "找不到执行脚本：$SCRIPT_PATH" >&2
    exit 1
fi

chmod +x "$SCRIPT_PATH"
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/.opc-companion/logs/inspect"

# 替换占位符；用 | 做分隔避免路径里的 / 冲突
sed -e "s|__SCRIPT_PATH__|$SCRIPT_PATH|g" \
    -e "s|__REPO_DIR__|$REPO_DIR|g" \
    -e "s|__HOME__|$HOME|g" \
    "$PLIST_TEMPLATE" > "$PLIST_DST"

launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo "已安装 $LABEL"
echo "  plist: $PLIST_DST"
echo "  触发：每天 00:00（若 Mac 睡眠，唤醒后 launchd 会补跑）"
echo ""
echo "手动触发：$0 --run-now"
echo "查看状态：launchctl list | grep $LABEL"
echo "卸载：$0 --uninstall"
