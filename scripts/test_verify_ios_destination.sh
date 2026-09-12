#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=verify_ios.sh
source "$ROOT_DIR/scripts/verify_ios.sh"

destinations='Available destinations:
  { platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
  { platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
  { platform:visionOS Simulator, id:VISION-DEVICE, name:Apple Vision Pro }
  { platform:iOS Simulator, arch:arm64, id:IPAD-SIMULATOR, OS:26.5, name:iPad (A16) }
  { platform:iOS Simulator, arch:arm64, id:IPHONE-SIMULATOR, OS:26.5, name:iPhone 17 Pro }'

actual="$(printf '%s\n' "$destinations" | simulator_id_from_destinations)"
test "$actual" = "IPHONE-SIMULATOR"

placeholder_only='{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }'
actual="$(printf '%s\n' "$placeholder_only" | simulator_id_from_destinations)"
test -z "$actual"

ipad_only='{ platform:iOS Simulator, arch:arm64, id:IPAD-ONLY-SIMULATOR, OS:26.5, name:iPad (A16) }'
actual="$(printf '%s\n' "$ipad_only" | simulator_id_from_destinations)"
test "$actual" = "IPAD-ONLY-SIMULATOR"

simctl_devices='{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.visionOS-26-5": [
      {"isAvailable": true, "udid": "VISION-SIMULATOR"}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
      {"isAvailable": false, "udid": "UNAVAILABLE-IOS-SIMULATOR"}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
      {"isAvailable": true, "name": "iPad (A16)", "udid": "IPAD-SIMCTL-SIMULATOR"},
      {"isAvailable": true, "name": "iPhone 17 Pro", "udid": "IPHONE-SIMCTL-SIMULATOR"}
    ]
  }
}'
actual="$(printf '%s\n' "$simctl_devices" | simulator_id_from_simctl)"
test "$actual" = "IPHONE-SIMCTL-SIMULATOR"

actual="$(printf '%s\n' '{}' | simulator_id_from_simctl)"
test -z "$actual"

ipad_only_simctl='{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
      {"isAvailable": true, "name": "iPad (A16)", "udid": "IPAD-ONLY-SIMCTL"}
    ]
  }
}'
actual="$(printf '%s\n' "$ipad_only_simctl" | simulator_id_from_simctl)"
test "$actual" = "IPAD-ONLY-SIMCTL"

actual="$(
  IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,id=EXPLICIT-SIMULATOR' \
    simulator_destination
)"
test "$actual" = "platform=iOS Simulator,id=EXPLICIT-SIMULATOR"

focused_ui_tests="$(
  printf '%s\n' \
    "CHANGELOG.md" \
    "iOS/MudsnoteCompanion/Features/Reader/RecentSearchView.swift" \
    "iOS/MudsnoteCompanion/Features/Reader/RecentSearchView.swift" \
    | focused_ui_tests_from_paths
)"
test "$focused_ui_tests" = \
  "MudsnoteCompanionUITests/MudsnoteCompanionUITests/testHomeOpensAsChronologicalCardsAndRightSwipeRevealsDirectory
MudsnoteCompanionUITests/MudsnoteCompanionUITests/testNewNoteFromSelectedFolderAppearsOnCurrentPage
MudsnoteCompanionUITests/MudsnoteCompanionUITests/testSelectedFolderIncludesNotesFromChildFoldersAndExposesSelection
MudsnoteCompanionUITests/MudsnoteCompanionUITests/testNotesTopBarMaterialAcrossHomeAndDirectoryStates"

focused_ui_tests="$(
  printf '%s\n' \
    "CHANGELOG.md" \
    "iOS/MudsnoteCompanion/Core/MarkdownFileStore.swift" \
    | focused_ui_tests_from_paths
)"
test -z "$focused_ui_tests"

focused_ui_tests="$(
  printf '%s\n' \
    "iOS/MudsnoteCompanion/Features/Capture/CaptureConsoleView.swift" \
    "iOS/MudsnoteCompanion/Core/MarkdownTagSyntax.swift" \
    "iOS/MudsnoteCompanion/Features/Reader/MarkdownPreviewView.swift" \
    | focused_ui_tests_from_paths
)"
test "$focused_ui_tests" = \
  "MudsnoteCompanionUITests/MudsnoteCompanionUITests/testCaptureCommandsStayInSingleRow
MudsnoteCompanionUITests/MudsnoteCompanionUITests/testHierarchicalCaptureTagStaysWholeAndOutOfTitle
MudsnoteCompanionUITests/MudsnoteCompanionUITests/testEditorToolbarAndHeaderScrollMatchTheUnifiedEditingModel
MudsnoteCompanionUITests/MudsnoteCompanionUITests/testEditorMentionLinksToAnotherNote"

scope_fixture="$(mktemp -d)"
trap 'rm -rf "$scope_fixture"' EXIT

git -C "$scope_fixture" init -q -b main
git -C "$scope_fixture" config user.email mudsnote-test@example.invalid
git -C "$scope_fixture" config user.name "Mudsnote Test"
printf 'fixture\n' >"$scope_fixture/README.md"
git -C "$scope_fixture" add README.md
git -C "$scope_fixture" commit -qm fixture
base_sha="$(git -C "$scope_fixture" rev-parse HEAD)"

mkdir -p "$scope_fixture/iOS/Fixture"
printf 'struct IOSFixture {}\n' >"$scope_fixture/iOS/Fixture/IOSFixture.swift"
git -C "$scope_fixture" add iOS/Fixture/IOSFixture.swift
git -C "$scope_fixture" commit -qm ios
ios_sha="$(git -C "$scope_fixture" rev-parse HEAD)"

changed_paths="$(
  MUDSNOTE_DIFF_BASE="$base_sha" MUDSNOTE_DIFF_HEAD="$ios_sha" \
    changed_paths_against_base "$scope_fixture"
)"
test "$changed_paths" = "iOS/Fixture/IOSFixture.swift"

printf 'struct MacFixture {}\n' >"$scope_fixture/MacFixture.swift"
git -C "$scope_fixture" add MacFixture.swift
git -C "$scope_fixture" commit -qm macos
mac_sha="$(git -C "$scope_fixture" rev-parse HEAD)"

platform_scope="$(
  MUDSNOTE_DIFF_BASE="$base_sha" MUDSNOTE_DIFF_HEAD="$ios_sha" \
    "$ROOT_DIR/scripts/detect_platform_scope.sh" "$scope_fixture"
)"
test "$platform_scope" = ios

platform_scope="$(
  MUDSNOTE_DIFF_BASE="$ios_sha" MUDSNOTE_DIFF_HEAD="$mac_sha" \
    "$ROOT_DIR/scripts/detect_platform_scope.sh" "$scope_fixture"
)"
test "$platform_scope" = macos

platform_scope="$(
  MUDSNOTE_DIFF_BASE="$base_sha" MUDSNOTE_DIFF_HEAD="$mac_sha" \
    "$ROOT_DIR/scripts/detect_platform_scope.sh" "$scope_fixture"
)"
test "$platform_scope" = both

if MUDSNOTE_DIFF_BASE="$base_sha" MUDSNOTE_DIFF_HEAD=missing \
  "$ROOT_DIR/scripts/detect_platform_scope.sh" "$scope_fixture" >/dev/null 2>&1; then
  echo "ERROR: invalid push range was accepted." >&2
  exit 1
fi

echo "verify_ios destination, focused UI, and platform scope routing passed"
