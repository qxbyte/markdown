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
DMG_STAGING_DIR="${DIST_DIR}/dmg-staging"
DMG_TEMP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-rw.dmg"
DMG_BACKGROUND_PATH="${DMG_STAGING_DIR}/.background/background.png"
DMG_MOUNT_DIR=""
DMG_DEVICE=""

cleanup_dmg() {
  if [[ -n "${DMG_DEVICE}" ]]; then
    hdiutil detach "${DMG_DEVICE}" -quiet > /dev/null 2>&1 || true
  fi
  rm -rf "${DMG_STAGING_DIR}"
  rm -f "${DMG_TEMP_PATH}"
}
trap cleanup_dmg EXIT

echo "▶ Building DMG..."
rm -f "${DMG_PATH}" "${DMG_TEMP_PATH}"
rm -rf "${DMG_STAGING_DIR}"
mkdir -p "${DMG_STAGING_DIR}/.background"
cp -R "${APP_PATH}" "${DMG_STAGING_DIR}/"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"
swift "${SCRIPT_DIR}/generate-dmg-background.swift" "${DMG_BACKGROUND_PATH}"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "${DMG_TEMP_PATH}"

ATTACH_OUTPUT="$(hdiutil attach "${DMG_TEMP_PATH}" -readwrite -noverify -noautoopen)"
DMG_DEVICE="$(printf "%s\n" "${ATTACH_OUTPUT}" | awk '/Apple_HFS/ { print $1; exit }')"
DMG_MOUNT_DIR="$(printf "%s\n" "${ATTACH_OUTPUT}" | awk '/Apple_HFS/ { print $3; exit }')"

if [[ -z "${DMG_DEVICE}" || -z "${DMG_MOUNT_DIR}" ]]; then
  echo "Failed to mount temporary DMG." >&2
  exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
  open POSIX file "${DMG_MOUNT_DIR}"
  delay 1
  tell disk "${APP_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 760, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background picture of viewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {170, 220}
    set position of item "Applications" of container window to {470, 220}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "${DMG_DEVICE}" -quiet
DMG_DEVICE=""

hdiutil convert "${DMG_TEMP_PATH}" -ov -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
rm -f "${DMG_TEMP_PATH}"
rm -rf "${DMG_STAGING_DIR}"

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
