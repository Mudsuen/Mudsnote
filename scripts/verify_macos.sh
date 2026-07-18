#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-pr}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PERFORMANCE_TESTS='StaysInteractiveAtSnapshotLimit|richMarkdownSerializationStaysInteractiveForDenseFormatting|cachedNoteVersionValidationDoesNotBlockKeyboardNavigation'

case "$MODE" in
  pr)
    swift test --skip "$PERFORMANCE_TESTS"
    ;;
  full)
    swift build -c release
    swift test
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
