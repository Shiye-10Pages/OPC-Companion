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

# 版本号单一真相源 = version.json；打包时 stamp 进 bundle 的 Info.plist（更新提示靠它比对本地/线上版本）
if [ -f "version.json" ]; then
    APP_VERSION="$(python3 -c "import json;print(json.load(open('version.json'))['version'])" 2>/dev/null || echo "")"
    if [ -n "$APP_VERSION" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
        echo "==> 版本 stamp: $APP_VERSION"
    fi
fi

# 复制 App 图标（Finder 中 .app 显示；本应用 LSUIElement 不进 Dock）
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
cp "Resources/ShiyeAI-Xiaohongshu-QR.png" "$APP_BUNDLE/Contents/Resources/"
# 企微二维码（反馈与诊断用）；未提供则跳过，不阻断构建
if [ -f "Resources/Wecom-QR.png" ]; then
    cp "Resources/Wecom-QR.png" "$APP_BUNDLE/Contents/Resources/"
else
    echo "==> 跳过 Wecom-QR.png（文件未提供，反馈区二维码将隐藏）"
fi

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
