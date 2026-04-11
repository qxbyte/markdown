#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MarkdownEditor"
BUNDLE_ID="com.local.markdowneditor"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_PATH="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_PATH}/Contents"

VERSION_INPUT="${1:-}"
if [[ -z "${VERSION_INPUT}" ]]; then
  VERSION_INPUT="${VERSION:-0.1.0}"
fi
VERSION="${VERSION_INPUT#v}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ICON_SRC="${ICON_SRC:-${PROJECT_ROOT}/assets/app-icon.png}"

echo "▶ Building release binary..."
swift build -c release

echo "▶ Preparing app bundle..."
rm -rf "${APP_PATH}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${CONTENTS_DIR}/MacOS/${APP_NAME}"
cp "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle/default.css" "${CONTENTS_DIR}/Resources/default.css"

echo "▶ Generating icon (optional)..."
if [[ -f "${ICON_SRC}" ]]; then
  ICONSET="${DIST_DIR}/AppIcon.iconset"
  mkdir -p "${ICONSET}"
  for size in 16 32 64 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SRC}" \
      --out "${ICONSET}/icon_${size}x${size}.png" > /dev/null 2>&1
    double=$((size * 2))
    sips -z "${double}" "${double}" "${ICON_SRC}" \
      --out "${ICONSET}/icon_${size}x${size}@2x.png" > /dev/null 2>&1
  done
  iconutil -c icns "${ICONSET}" -o "${CONTENTS_DIR}/Resources/AppIcon.icns"
  rm -rf "${ICONSET}"
  echo "   Icon generated."
else
  echo "   Icon source not found: ${ICON_SRC} (skip)"
fi

echo "▶ Writing Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
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

echo "▶ Ad-hoc signing..."
strip "${CONTENTS_DIR}/MacOS/${APP_NAME}"
codesign --force --sign - "${CONTENTS_DIR}/MacOS/${APP_NAME}"
codesign --force --sign - "${APP_PATH}"

DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
PKG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"

echo "▶ Building DMG..."
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_PATH}" -ov -format UDZO "${DMG_PATH}"

echo "▶ Building PKG..."
rm -f "${PKG_PATH}"
pkgbuild \
  --component "${APP_PATH}" \
  --install-location "/Applications" \
  --identifier "${BUNDLE_ID}" \
  --version "${VERSION}" \
  "${PKG_PATH}"

echo "✅ Release assets generated:"
echo "   - ${DMG_PATH}"
echo "   - ${PKG_PATH}"
