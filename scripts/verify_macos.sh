#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-pr}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PERFORMANCE_TESTS='StaysInteractiveAtSnapshotLimit|richMarkdownSerializationStaysInteractiveForDenseFormatting|cachedNoteVersionValidationDoesNotBlockKeyboardNavigation'

# SwiftPM's generated async-main host can exit 0 after AppKit posts a
# nested-loop stop event. Load the same test bundle in a synchronous AppKit host.
run_tests() {
  local configuration="$1"
  shift
  if [[ "$configuration" == "release" ]]; then
    swift build -c release --build-tests -Xswiftc -enable-testing
  else
    swift build -c debug --build-tests
  fi
  local bin_dir
  bin_dir="$(swift build -c "$configuration" --show-bin-path)"
  local frameworks
  frameworks="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
  swiftc -parse-as-library scripts/MacOSTestRunner.swift \
    -module-cache-path "$bin_dir/ModuleCache" \
    -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
    -o "$bin_dir/MudsnoteAppKitTestHost"
  "$bin_dir/MudsnoteAppKitTestHost" \
    --test-bundle-path "$bin_dir/MudsnotePackageTests.xctest/Contents/MacOS/MudsnotePackageTests" "$@"
}

case "$MODE" in
  pr)
    run_tests debug --skip "$PERFORMANCE_TESTS"
    ;;
  full)
    run_tests debug --skip "$PERFORMANCE_TESTS"
    if [[ -n "${CI:-}" ]]; then
      swift build -c release
    else
      run_tests release --filter "$PERFORMANCE_TESTS"
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
