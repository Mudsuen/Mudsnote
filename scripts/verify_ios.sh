#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-pr}"
FULL_PHASE="${IOS_VERIFY_FULL_PHASE:-all}"
PARALLEL_FULL="${IOS_VERIFY_PARALLEL_FULL:-0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/iOS/MudsnoteCompanion.xcodeproj"
SCHEME="MudsnoteCompanion"
DERIVED_DATA_PATH="${IOS_VERIFY_DERIVED_DATA_PATH:-$ROOT_DIR/build/IOSVerifyDerivedData}"
RELEASE_DERIVED_DATA_PATH="${IOS_VERIFY_RELEASE_DERIVED_DATA_PATH:-$ROOT_DIR/build/IOSReleaseVerifyDerivedData}"

cd "$ROOT_DIR"

simulator_id_from_destinations() {
  awk '
    /platform:iOS Simulator,/ && $0 !~ /placeholder/ {
      destination = $0
      sub(/^.*id:/, "", destination)
      sub(/[,}].*$/, "", destination)
      if ($0 ~ /name:iPhone/) {
        print destination
        found_iphone = 1
        exit
      }
      if (fallback == "") {
        fallback = destination
      }
    }
    END {
      if (!found_iphone && fallback != "") {
        print fallback
      }
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

fallback = None
for runtime, devices in payload.get("devices", {}).items():
    if ".iOS-" not in runtime:
        continue
    for device in devices:
        identifier = device.get("udid")
        if device.get("isAvailable") and identifier:
            if str(device.get("name", "")).startswith("iPhone"):
                print(identifier)
                raise SystemExit(0)
            if fallback is None:
                fallback = identifier

if fallback is not None:
    print(fallback)
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

changed_paths_against_base() {
  local root="${1:-.}"
  local diff_base="${MUDSNOTE_DIFF_BASE:-}"
  local diff_head="${MUDSNOTE_DIFF_HEAD:-}"
  local base_ref=""

  if [[ -n "$diff_base" || -n "$diff_head" ]]; then
    if [[ -z "$diff_base" || -z "$diff_head" ]]; then
      echo "ERROR: MUDSNOTE_DIFF_BASE and MUDSNOTE_DIFF_HEAD must be provided together." >&2
      return 2
    fi
    git -C "$root" rev-parse --verify "$diff_base^{commit}" >/dev/null
    git -C "$root" rev-parse --verify "$diff_head^{commit}" >/dev/null
    git -C "$root" diff --name-only "$diff_base" "$diff_head" | sort -u
    return
  fi

  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    base_ref="origin/$GITHUB_BASE_REF"
  elif git -C "$root" show-ref --verify --quiet refs/remotes/origin/main; then
    base_ref="origin/main"
  fi

  if [[ -n "$base_ref" ]]; then
    {
      git -C "$root" diff --name-only "$(git -C "$root" merge-base HEAD "$base_ref")..HEAD"
      git -C "$root" diff --name-only
      git -C "$root" diff --cached --name-only
    } | sort -u
  else
    {
      git -C "$root" diff --name-only HEAD
      git -C "$root" diff --cached --name-only
    } | sort -u
  fi
}

focused_ui_tests_from_paths() {
  local needs_directory_drawer_test=0
  local needs_capture_test=0
  local needs_editor_test=0
  local path

  while IFS= read -r path; do
    case "$path" in
      iOS/MudsnoteCompanion/Features/Reader/RecentSearchView.swift)
        needs_directory_drawer_test=1
        ;;
      iOS/MudsnoteCompanion/Features/Capture/CaptureConsoleView.swift|\
      iOS/MudsnoteCompanion/Features/Capture/TargetMenuView.swift|\
      iOS/MudsnoteCompanion/Core/MarkdownTagSyntax.swift|\
      iOS/MudsnoteCompanion/Design/MudsnoteTokens.swift)
        needs_capture_test=1
        ;;
      iOS/MudsnoteCompanion/Features/Reader/MarkdownPreviewView.swift)
        needs_editor_test=1
        ;;
    esac
  done

  if [[ "$needs_directory_drawer_test" == "1" ]]; then
    printf '%s\n' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testHomeOpensAsChronologicalCardsAndRightSwipeRevealsDirectory' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testNewNoteFromSelectedFolderAppearsOnCurrentPage' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testSelectedFolderIncludesNotesFromChildFoldersAndExposesSelection' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testNotesTopBarMaterialAcrossHomeAndDirectoryStates'
  fi
  if [[ "$needs_capture_test" == "1" ]]; then
    printf '%s\n' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testCaptureCommandsStayInSingleRow' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testHierarchicalCaptureTagStaysWholeAndOutOfTitle'
  fi
  if [[ "$needs_editor_test" == "1" ]]; then
    printf '%s\n' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testEditorToolbarAndHeaderScrollMatchTheUnifiedEditingModel' \
      'MudsnoteCompanionUITests/MudsnoteCompanionUITests/testEditorMentionLinksToAnotherNote'
  fi
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return
fi

python3 scripts/validate_ios_app_store_metadata.py

case "$FULL_PHASE" in
  all|tests|release)
    ;;
  *)
    echo "ERROR: invalid IOS_VERIFY_FULL_PHASE: $FULL_PHASE" >&2
    exit 2
    ;;
esac

case "$PARALLEL_FULL" in
  0|1)
    ;;
  *)
    echo "ERROR: invalid IOS_VERIFY_PARALLEL_FULL: $PARALLEL_FULL" >&2
    exit 2
    ;;
esac

run_full_tests() {
  local destination
  local focused_ui_test
  local focused_ui_output
  local -a test_selectors

  destination="$(simulator_destination)"
  test_selectors=(-only-testing:MudsnoteCompanionTests)
  if ! focused_ui_output="$(
    changed_paths_against_base | focused_ui_tests_from_paths
  )"; then
    echo "ERROR: failed to determine focused iOS UI tests." >&2
    exit 1
  fi
  while IFS= read -r focused_ui_test; do
    if [[ -n "$focused_ui_test" ]]; then
      test_selectors+=("-only-testing:$focused_ui_test")
    fi
  done <<<"$focused_ui_output"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    -parallel-testing-enabled NO \
    "${test_selectors[@]}" \
    test
}

run_release_build() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$RELEASE_DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build
}

case "$MODE" in
  pr)
    destination="$(simulator_destination)"
    if ! focused_ui_output="$(
      changed_paths_against_base | focused_ui_tests_from_paths
    )"; then
      echo "ERROR: failed to determine focused iOS UI tests." >&2
      exit 1
    fi
    focused_ui_tests=()
    while IFS= read -r focused_ui_test; do
      if [[ -n "$focused_ui_test" ]]; then
        focused_ui_tests+=("-only-testing:$focused_ui_test")
      fi
    done <<<"$focused_ui_output"

    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination "$destination" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      COMPILER_INDEX_STORE_ENABLE=NO \
      build-for-testing

    if (( ${#focused_ui_tests[@]} > 0 )); then
      xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        COMPILER_INDEX_STORE_ENABLE=NO \
        -parallel-testing-enabled NO \
        "${focused_ui_tests[@]}" \
        test-without-building
    fi
    ;;
  full)
    if [[ "$FULL_PHASE" == "all" && "$PARALLEL_FULL" == "1" ]]; then
      release_log="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mudsnote-ios-release.XXXXXX")"
      trap 'rm -f "$release_log"' EXIT

      echo "Starting Release build concurrently with Debug tests."
      run_release_build >"$release_log" 2>&1 &
      release_pid=$!

      set +e
      run_full_tests
      tests_status=$?
      wait "$release_pid"
      release_status=$?
      set -e

      echo "Release build output:"
      cat "$release_log"
      if [[ "$tests_status" != "0" || "$release_status" != "0" ]]; then
        echo "ERROR: iOS verification failed (tests=$tests_status, release=$release_status)." >&2
        exit 1
      fi
    else
      if [[ "$FULL_PHASE" == "all" || "$FULL_PHASE" == "tests" ]]; then
        run_full_tests
      fi
      if [[ "$FULL_PHASE" == "all" || "$FULL_PHASE" == "release" ]]; then
        run_release_build
      fi
    fi
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
