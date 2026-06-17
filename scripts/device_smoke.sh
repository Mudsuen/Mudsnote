#!/usr/bin/env bash
set -euo pipefail

PROJECT="iOS/MudsnoteCompanion.xcodeproj"
SCHEME="MudsnoteCompanion"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DeviceDerivedData}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/MudsnoteCompanion.app"
BUNDLE_ID="app.mudsnote.companion"

cd "$(dirname "$0")/.."

if [[ -z "${XCODE_DEVICE_ID:-}" ]]; then
  XCODE_DEVICE_ID="$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
      | sed -nE 's/.*platform:iOS,.*id:([^,}]+).*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "${DEVICETL_DEVICE_ID:-}" ]]; then
  DEVICETL_DEVICE_ID="$(
    xcrun devicectl list devices \
      | awk '/iPhone/ && ($4 == "connected" || $4 == "available") { print $3; exit }'
  )"
fi

if [[ -z "$XCODE_DEVICE_ID" || -z "$DEVICETL_DEVICE_ID" ]]; then
  echo "No connected iOS device destination found. Connect and unlock the iPhone, then retry." >&2
  exit 1
fi

echo "Building $SCHEME for Xcode destination $XCODE_DEVICE_ID"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$XCODE_DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  build

echo "Installing $APP_PATH"
xcrun devicectl device install app --device "$DEVICETL_DEVICE_ID" "$APP_PATH"

echo "Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICETL_DEVICE_ID" "$BUNDLE_ID"

echo "Device smoke passed for $BUNDLE_ID"
