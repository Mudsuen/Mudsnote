#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-pr}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/iOS/MudsnoteCompanion.xcodeproj"
SCHEME="MudsnoteCompanion"
DERIVED_DATA_PATH="${IOS_VERIFY_DERIVED_DATA_PATH:-$ROOT_DIR/build/IOSVerifyDerivedData}"

cd "$ROOT_DIR"

simulator_id_from_destinations() {
  awk '
    /platform:iOS Simulator,/ && $0 !~ /placeholder/ {
      destination = $0
      sub(/^.*id:/, "", destination)
      sub(/[,}].*$/, "", destination)
      print destination
      exit
    }
  '
}

simulator_id_from_simctl() {
  python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError):
    raise SystemExit(0)

for runtime, devices in payload.get("devices", {}).items():
    if ".iOS-" not in runtime:
        continue
    for device in devices:
        identifier = device.get("udid")
        if device.get("isAvailable") and identifier:
            print(identifier)
            raise SystemExit(0)
'
}

simulator_destination() {
  if [[ -n "${IOS_SIMULATOR_DESTINATION:-}" ]]; then
    printf '%s\n' "$IOS_SIMULATOR_DESTINATION"
    return
  fi

  local simulator_id destinations simctl_devices
  destinations="$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
      || true
  )"
  simulator_id="$(printf '%s\n' "$destinations" | simulator_id_from_destinations)"
  if [[ -z "$simulator_id" ]]; then
    simctl_devices="$(xcrun simctl list devices available --json 2>/dev/null || true)"
    simulator_id="$(printf '%s\n' "$simctl_devices" | simulator_id_from_simctl)"
  fi
  if [[ -z "$simulator_id" ]]; then
    echo "No available concrete iOS Simulator destination found." >&2
    exit 1
  fi
  printf 'id=%s\n' "$simulator_id"
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return
fi

python3 scripts/validate_ios_app_store_metadata.py

case "$MODE" in
  pr)
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      build-for-testing
    ;;
  full)
    destination="$(simulator_destination)"
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination "$destination" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      -only-testing:MudsnoteCompanionTests \
      test
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination 'generic/platform=iOS' \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      build
    ;;
  live)
    if [[ -n "${CI:-}" ]]; then
      echo "ERROR: iOS live verification is local-only and must not run in CI." >&2
      exit 2
    fi
    ./scripts/device_smoke.sh
    ;;
  *)
    echo "Usage: ./scripts/verify_ios.sh {pr|full|live}" >&2
    exit 2
    ;;
esac
