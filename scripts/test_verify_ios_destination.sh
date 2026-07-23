#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=verify_ios.sh
source "$ROOT_DIR/scripts/verify_ios.sh"

destinations='Available destinations:
  { platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
  { platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
  { platform:visionOS Simulator, id:VISION-DEVICE, name:Apple Vision Pro }
  { platform:iOS Simulator, arch:arm64, id:REAL-IOS-SIMULATOR, OS:26.5, name:iPhone 17 Pro }
  { platform:iOS Simulator, arch:arm64, id:SECOND-IOS-SIMULATOR, OS:26.5, name:iPad (A16) }'

actual="$(printf '%s\n' "$destinations" | simulator_id_from_destinations)"
test "$actual" = "REAL-IOS-SIMULATOR"

placeholder_only='{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }'
actual="$(printf '%s\n' "$placeholder_only" | simulator_id_from_destinations)"
test -z "$actual"

echo "verify_ios simulator destination parsing passed"
