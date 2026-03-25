#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/dist/build"
APP_DIR="${ROOT_DIR}/dist/QuickMarkdown.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

mkdir -p /tmp/codex-swift-module-cache /tmp/codex-xdg-cache /tmp/codex-home
HOME=/tmp/codex-home \
XDG_CACHE_HOME=/tmp/codex-xdg-cache \
SWIFT_MODULECACHE_PATH=/tmp/codex-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/codex-swift-module-cache \
swift build -c release --scratch-path "${BUILD_DIR}"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"

cp "${BUILD_DIR}/arm64-apple-macosx/release/quickmarkdown" "${MACOS_DIR}/QuickMarkdown"
chmod +x "${MACOS_DIR}/QuickMarkdown"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>QuickMarkdown</string>
    <key>CFBundleExecutable</key>
    <string>QuickMarkdown</string>
    <key>CFBundleIdentifier</key>
    <string>local.codex.quickmarkdown</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>QuickMarkdown</string>
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

echo "Packaged app at: ${APP_DIR}"
