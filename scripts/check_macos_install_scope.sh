#!/bin/zsh

set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
APP_DIR="/Applications/Mudsnote.app"

if [[ "${MUDSNOTE_ALLOW_IOS_ONLY_MAC_INSTALL:-0}" == "1" ]]; then
    exit 0
fi

if ! git -C "${ROOT_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

BASE_REF="${MUDSNOTE_PACKAGE_BASE_REF:-main}"
if ! git -C "${ROOT_DIR}" rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
    exit 0
fi

BASE_COMMIT="$(git -C "${ROOT_DIR}" merge-base HEAD "${BASE_REF}")"
CHANGED_FILES="$({
    git -C "${ROOT_DIR}" diff --name-only "${BASE_COMMIT}...HEAD"
    git -C "${ROOT_DIR}" diff --name-only
    git -C "${ROOT_DIR}" diff --cached --name-only
} | sort -u)"
MAC_RELEVANT_FILES="$(printf '%s\n' "${CHANGED_FILES}" | grep -Ev '^(iOS/|docs/|agent-memory/|\.github/|\.gitignore$|[^/]+\.md$)' || true)"

if [[ -n "${CHANGED_FILES}" && -z "${MAC_RELEVANT_FILES}" ]]; then
    echo "ERROR: refusing to overwrite ${APP_DIR} from an iOS-only worktree." >&2
    echo "Use the iOS Xcode/device flow. For an intentional exception, set MUDSNOTE_ALLOW_IOS_ONLY_MAC_INSTALL=1." >&2
    exit 2
fi
