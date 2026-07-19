#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/dist/build"
APP_DIR="/Applications/Mudsnote.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

"${ROOT_DIR}/scripts/check_macos_install_scope.sh" "${ROOT_DIR}"

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
    <string>zh-Hans</string>
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
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.text</string>
            </array>
            <key>UTTypeDescription</key>
            <string>Markdown Document</string>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                </array>
                <key>public.mime-type</key>
                <string>text/markdown</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

xattr -cr "${APP_DIR}" || true
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ { print $2; exit }')"
if [[ -z "${SIGN_IDENTITY}" ]]; then
    SIGN_IDENTITY="-"
fi
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}" >/dev/null

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP_DIR}"
pkill -f '/Applications/Mudsnote.app/Contents/MacOS/Mudsnote' || true
sleep 1
open -a "${APP_DIR}"

echo "Packaged app at: ${APP_DIR}"
echo "Signed with: ${SIGN_IDENTITY}"
