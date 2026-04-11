#!/usr/bin/env bash
# package-app.sh — 将 MarkdownEditor 打包为可直接使用的 .app
set -euo pipefail

APP_NAME="MarkdownEditor"
BUNDLE_ID="com.local.markdowneditor"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app/Contents"
ICON_SRC="${HOME}/Desktop/图标.png"

echo "▶ 编译 Release..."
swift build -c release

echo "▶ 创建 .app 目录结构..."
rm -rf "dist/${APP_NAME}.app"
mkdir -p "${APP_DIR}/MacOS"
mkdir -p "${APP_DIR}/Resources"

echo "▶ 拷贝可执行文件..."
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/MacOS/${APP_NAME}"

echo "▶ 拷贝资源文件..."
cp "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle/default.css" \
   "${APP_DIR}/Resources/default.css"

echo "▶ 生成 App 图标..."
if [ -f "${ICON_SRC}" ]; then
    ICONSET="dist/AppIcon.iconset"
    mkdir -p "${ICONSET}"
    # macOS iconset 所需尺寸
    for size in 16 32 64 128 256 512; do
        sips -z ${size} ${size} "${ICON_SRC}" \
             --out "${ICONSET}/icon_${size}x${size}.png"      > /dev/null 2>&1
        double=$((size * 2))
        sips -z ${double} ${double} "${ICON_SRC}" \
             --out "${ICONSET}/icon_${size}x${size}@2x.png"   > /dev/null 2>&1
    done
    iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Resources/AppIcon.icns"
    rm -rf "${ICONSET}"
    echo "   图标已生成：AppIcon.icns"
else
    echo "   ⚠️  未找到 ${ICON_SRC}，跳过图标"
fi

echo "▶ 写入 Info.plist..."
cat > "${APP_DIR}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>        <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>              <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>       <string>Markdown Editor</string>
  <key>CFBundleVersion</key>           <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>  <string>Markdown Document</string>
      <key>CFBundleTypeRole</key>  <string>Editor</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>net.daringfireball.markdown</string>
        <string>public.plain-text</string>
      </array>
      <key>CFBundleTypeExtensions</key>
      <array><string>md</string><string>markdown</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "▶ 去除调试符号..."
strip "${APP_DIR}/MacOS/${APP_NAME}"

echo "▶ Ad-hoc 签名..."
codesign --force --sign - "${APP_DIR}/MacOS/${APP_NAME}"
codesign --force --sign - "dist/${APP_NAME}.app"

echo ""
echo "✅ 打包完成：dist/${APP_NAME}.app"
echo "   大小：$(du -sh "dist/${APP_NAME}.app" | cut -f1)"
echo ""
echo "▶ 安装到 Applications 并刷新图标缓存..."
cp -r "dist/${APP_NAME}.app" /Applications/
# 通知 Launch Services 重新注册 app（刷新图标 + 文件关联）
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f /Applications/${APP_NAME}.app
echo "✅ 已安装：/Applications/${APP_NAME}.app"
