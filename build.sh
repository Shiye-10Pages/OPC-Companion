#!/bin/bash
set -euo pipefail

APP_NAME="OPCCompanion"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> 编译 Release..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

echo "==> 打包 ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制二进制
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 复制 Info.plist
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/"

echo "==> 验证 bundle..."
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
test -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Ad-hoc 签名
echo "==> 签名并校验..."
codesign -s - --force --deep "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> 完成！"
echo ""
echo "运行方式："
echo "  open $APP_BUNDLE"
echo ""
echo "或直接运行二进制："
echo "  ./$APP_BUNDLE/Contents/MacOS/$APP_NAME"
