#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="OPCCompanion.app"
INSTALL_DIR="${OPC_INSTALL_DIR:-$HOME/Applications}"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "错误：OPC 伴侣目前仅支持 macOS。"
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "需要先安装 Xcode Command Line Tools。"
    echo "系统会打开安装窗口。安装完成后，请再次运行本命令。"
    xcode-select --install || true
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "错误：没有找到 Swift。请先完成 Xcode Command Line Tools 安装。"
    exit 1
fi

echo "==> 编译并打包 OPC 伴侣..."
cd "$REPO_DIR"
./build.sh

echo "==> 安装到 $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
ditto "$REPO_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"

echo "==> 启动 OPC 伴侣..."
open "$INSTALL_DIR/$APP_NAME"
echo ""
echo "安装完成。首次使用：点击菜单栏气泡图标，进入设置，填写任意一个支持服务商的 API Key。"
