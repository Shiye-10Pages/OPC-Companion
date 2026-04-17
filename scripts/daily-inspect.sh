#!/bin/bash
# 由 launchd 每天 00:00 触发。
# 跑 Claude CLI 巡检 agent，写报告到 ~/.opc-companion/logs/inspect/YYYY-MM-DD.md，
# 用 osascript 发 macOS 横幅通知。

set -uo pipefail

LOG_DIR="$HOME/.opc-companion/logs/inspect"
mkdir -p "$LOG_DIR"
DATE=$(date +%Y-%m-%d)
REPORT="$LOG_DIR/$DATE.md"

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/inspect-prompt.md"

notify() {
    local title="$1"
    local body="$2"
    # 转义双引号
    body=${body//\"/\\\"}
    osascript -e "display notification \"$body\" with title \"$title\" subtitle \"$DATE\"" 2>/dev/null || true
}

if [ ! -x "$CLAUDE_BIN" ]; then
    notify "OPC 巡检失败" "Claude CLI not found at $CLAUDE_BIN"
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    notify "OPC 巡检失败" "Prompt file missing: $PROMPT_FILE"
    exit 1
fi

{
    echo "# OPC 伴侣每日巡检 — $DATE"
    echo ""
    echo "开始时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    echo "---"
    echo ""
    "$CLAUDE_BIN" -p --model claude-haiku-4-5-20251001 "$(cat "$PROMPT_FILE")" 2>&1
    echo ""
    echo "---"
    echo "结束时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
} > "$REPORT"

# 摘要：取最后 10 行非空内容，截 200 字符，作为通知正文
SUMMARY=$(tail -n 20 "$REPORT" | grep -v '^$' | tail -n 5 | tr '\n' ' ' | cut -c1-200)
if [ -z "$SUMMARY" ]; then
    SUMMARY="报告已写入 $REPORT"
fi

notify "OPC 伴侣巡检完成" "$SUMMARY"
