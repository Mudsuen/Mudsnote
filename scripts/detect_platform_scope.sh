#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo none
  exit 0
fi

if git -C "$ROOT_DIR" show-ref --verify --quiet refs/remotes/origin/main; then
  BASE_REF=origin/main
elif git -C "$ROOT_DIR" rev-parse --verify main^{commit} >/dev/null 2>&1; then
  BASE_REF=main
else
  BASE_REF=HEAD
fi

BASE_COMMIT="$(git -C "$ROOT_DIR" merge-base HEAD "$BASE_REF")"
CHANGED_FILES="$({
  git -C "$ROOT_DIR" diff --name-only "$BASE_COMMIT...HEAD"
  git -C "$ROOT_DIR" diff --name-only
  git -C "$ROOT_DIR" diff --cached --name-only
} | sort -u)"

has_macos=0
has_ios=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  case "$path" in
    iOS/*|scripts/device_smoke.sh|scripts/validate_ios_app_store_metadata.py|scripts/verify_ios.sh)
      has_ios=1
      ;;
    docs/*|agent-memory/*|.github/*|*.md|.gitignore|.devflow.yaml)
      ;;
    scripts/generate_ios_companion_icon.sh)
      has_ios=1
      ;;
    *)
      has_macos=1
      ;;
  esac
done <<< "$CHANGED_FILES"

if [[ "$has_macos" == "1" && "$has_ios" == "1" ]]; then
  echo both
elif [[ "$has_ios" == "1" ]]; then
  echo ios
elif [[ "$has_macos" == "1" ]]; then
  echo macos
else
  echo none
fi
