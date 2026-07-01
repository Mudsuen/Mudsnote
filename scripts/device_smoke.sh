#!/usr/bin/env bash
set -euo pipefail

PROJECT="iOS/MudsnoteCompanion.xcodeproj"
SCHEME="MudsnoteCompanion"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DeviceDerivedData}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/MudsnoteCompanion.app"
BUNDLE_ID="app.mudsnote.companion"
DEVICECTL_DEVICE_ID="${DEVICECTL_DEVICE_ID:-${DEVICETL_DEVICE_ID:-}}"

cd "$(dirname "$0")/.."

if [[ -z "${XCODE_DEVICE_ID:-}" ]]; then
  XCODE_DEVICE_ID="$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
      | sed -nE 's/.*platform:iOS,.*id:([^,}]+).*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "${DEVICECTL_DEVICE_ID:-}" ]]; then
  DEVICECTL_DEVICE_ID="$(
    xcrun devicectl list devices \
      | awk 'NR > 2 && /iPhone/ && ($4 == "connected" || $4 == "available") { print $3; exit }'
  )"
fi

if [[ -z "$XCODE_DEVICE_ID" || -z "$DEVICECTL_DEVICE_ID" ]]; then
  echo "No connected iOS device destination found. Connect and unlock the iPhone, then retry." >&2
  exit 1
fi

echo "Checking developer disk image services for CoreDevice $DEVICECTL_DEVICE_ID"
DDI_OUTPUT="$(mktemp)"
if ! xcrun devicectl device info ddiServices --device "$DEVICECTL_DEVICE_ID" >"$DDI_OUTPUT" 2>&1; then
  cat "$DDI_OUTPUT" >&2
  if grep -q "kAMDMobileImageMounterDeviceLocked\\|DeviceLocked\\|device is locked" "$DDI_OUTPUT"; then
    echo "" >&2
    echo "The iPhone is still locked for Developer Disk Image mounting." >&2
    echo "Unlock the phone, keep the screen awake, accept any Trust/Developer prompts, then rerun scripts/device_smoke.sh." >&2
  fi
  rm -f "$DDI_OUTPUT"
  exit 1
fi
rm -f "$DDI_OUTPUT"

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
xcrun devicectl device install app --device "$DEVICECTL_DEVICE_ID" "$APP_PATH"

echo "Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICECTL_DEVICE_ID" "$BUNDLE_ID"

echo "Device smoke passed for $BUNDLE_ID"
