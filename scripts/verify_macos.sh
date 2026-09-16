#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-pr}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

run_macos_tests() {
    local configuration="$1"
    shift
    swift build --build-tests -c "$configuration" -Xswiftc -enable-testing
    local bin_path developer_dir frameworks runner
    bin_path="$(swift build -c "$configuration" --show-bin-path)"
    developer_dir="$(xcode-select -p)"
    frameworks="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
    runner="$bin_path/mudsnote-macos-test-runner"
    xcrun swiftc -parse-as-library "$ROOT_DIR/scripts/MacOSTestMain.swift" \
        -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -o "$runner"
    MUDSNOTE_TEST_BUNDLE_PATH="$bin_path/MudsnotePackageTests.xctest/Contents/MacOS/MudsnotePackageTests" \
        "$runner" "$@"
}

PERFORMANCE_TESTS='StaysInteractiveAtSnapshotLimit|richMarkdownSerializationStaysInteractiveForDenseFormatting|cachedNoteVersionValidationDoesNotBlockKeyboardNavigation'

case "$MODE" in
  pr)
    run_macos_tests debug --skip "$PERFORMANCE_TESTS"
    ;;
  full)
    run_macos_tests debug --skip "$PERFORMANCE_TESTS"
    if [[ -n "${CI:-}" ]]; then
      swift build -c release
    else
      run_macos_tests release --filter "$PERFORMANCE_TESTS"
    fi
    ;;
  live)
    if [[ -n "${CI:-}" ]]; then
      echo "ERROR: macOS live verification is local-only and must not run in CI." >&2
      exit 2
    fi
    ./scripts/package_app.sh
    ;;
  *)
    echo "Usage: ./scripts/verify_macos.sh {pr|full|live}" >&2
    exit 2
    ;;
esac
