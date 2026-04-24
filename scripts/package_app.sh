#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/dist/build"
APP_DIR="/Applications/Mudsnote.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

"${ROOT_DIR}/scripts/generate_icon_assets.sh"

mkdir -p /tmp/codex-swift-module-cache /tmp/codex-xdg-cache /tmp/codex-home
HOME=/tmp/codex-home \
XDG_CACHE_HOME=/tmp/codex-xdg-cache \
SWIFT_MODULECACHE_PATH=/tmp/codex-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/codex-swift-module-cache \
swift build -c release --scratch-path "${BUILD_DIR}"

rm -rf "${APP_DIR}"
rm -rf /Applications/QuickMarkdown.app
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILD_DIR}/arm64-apple-macosx/release/mudsnote" "${MACOS_DIR}/Mudsnote"
chmod +x "${MACOS_DIR}/Mudsnote"
cp "${ROOT_DIR}/assets/generated/MudsnoteAppIcon.icns" "${RESOURCES_DIR}/MudsnoteAppIcon.icns"
cp "${ROOT_DIR}/assets/generated/MudsnoteStatusTemplate.png" "${RESOURCES_DIR}/MudsnoteStatusTemplate.png"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Mudsnote</string>
    <key>CFBundleExecutable</key>
    <string>Mudsnote</string>
    <key>CFBundleIconFile</key>
    <string>MudsnoteAppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.codex.mudsnote</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mudsnote</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

pkill -f '/Applications/Mudsnote.app/Contents/MacOS/Mudsnote' || true
sleep 1
open -a "${APP_DIR}"

echo "Packaged app at: ${APP_DIR}"
