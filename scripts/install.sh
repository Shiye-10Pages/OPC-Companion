#!/bin/bash
set -euo pipefail

REPO_URL="${OPC_REPO_URL:-https://github.com/Shiye-10Pages/OPC-Companion.git}"
BRANCH="${OPC_BRANCH:-feature/focused-conversation-memory}"
SOURCE_DIR="${OPC_SOURCE_DIR:-$HOME/.opc-companion/source}"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "错误：OPC 伴侣目前仅支持 macOS。"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "需要先安装 Xcode Command Line Tools。"
    echo "系统会打开安装窗口。安装完成后，请再次运行本命令。"
    xcode-select --install || true
    exit 1
fi

mkdir -p "$(dirname "$SOURCE_DIR")"

if [ -d "$SOURCE_DIR/.git" ]; then
    echo "==> 更新 OPC 伴侣源码..."
    git -C "$SOURCE_DIR" fetch origin "$BRANCH"
    git -C "$SOURCE_DIR" checkout "$BRANCH"
    git -C "$SOURCE_DIR" pull --ff-only origin "$BRANCH"
elif [ -e "$SOURCE_DIR" ]; then
    echo "错误：$SOURCE_DIR 已存在，但不是 OPC 伴侣源码目录。"
    echo "请移动或删除该目录后重试。"
    exit 1
else
    echo "==> 下载 OPC 伴侣源码..."
    git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$SOURCE_DIR"
fi

"$SOURCE_DIR/scripts/install-local.sh"
