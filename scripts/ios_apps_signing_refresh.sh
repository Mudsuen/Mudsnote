#!/usr/bin/env bash
set -euo pipefail

# One entry point for refreshing and installing the user's locally developed
# iOS apps. Mudsnote keeps its defensive profile backup/recovery implementation
# in ios_signing_refresh.sh; BadgeAnimation is an independent Xcode project.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUDSNOTE_REFRESH="$ROOT_DIR/scripts/ios_signing_refresh.sh"
BADGE_ROOT="${BADGE_ANIMATION_ROOT:-/Users/Donald/Documents/Codex/2026-08-25/jl/work/ios-badge-animation}"
BADGE_PROJECT="$BADGE_ROOT/BadgeAnimation.xcodeproj"
BADGE_DERIVED_DATA="$BADGE_ROOT/build/SigningRefreshDerivedData"
BADGE_APP="$BADGE_DERIVED_DATA/Build/Products/Debug-iphoneos/BadgeAnimation.app"
BADGE_BUNDLE_ID="com.codex.badgeanimation"
STATE_DIR="${MUDSNOTE_IOS_SIGNING_STATE_DIR:-${HOME:-/tmp}/Library/Application Support/Mudsnote}"
BADGE_PENDING_PATH="$STATE_DIR/badge-animation-signing-refresh-needs-install"
RENEWAL_THRESHOLD_SECONDS="${MUDSNOTE_IOS_SIGNING_RENEWAL_THRESHOLD_SECONDS:-172800}"

AUTO_INSTALL=0
AUTO_LAUNCH=0
DRY_RUN=0
MODE=run

profile_expiration_epoch() {
  local app="$1" expiration
  [[ -f "$app/embedded.mobileprovision" ]] || return 1
  expiration="$(security cms -D -i "$app/embedded.mobileprovision" 2>/dev/null \
    | plutil -extract ExpirationDate raw -o - - 2>/dev/null)" || return 1
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s' 2>/dev/null
}

badge_requires_refresh() {
  local expiration now
  [[ -d "$BADGE_APP" ]] || return 0
  expiration="$(profile_expiration_epoch "$BADGE_APP")" || return 0
  now="$(date '+%s')"
  (( expiration - now <= RENEWAL_THRESHOLD_SECONDS ))
}

available_iphone_id() {
  xcrun devicectl list devices 2>&1 \
    | awk 'NR > 2 && /iPhone/ && ($4 == "connected" || $4 == "available") { print $3; exit }'
}

refresh_badge() {
  local destination="generic/platform=iOS" device_id
  [[ -d "$BADGE_PROJECT" ]] || { echo "BadgeAnimation project not found: $BADGE_PROJECT" >&2; return 1; }
  device_id="$(xcodebuild -project "$BADGE_PROJECT" -scheme BadgeAnimation -showdestinations 2>/dev/null \
    | awk '/Available destinations/ { available=1; next } /Ineligible destinations/ { available=0 } available && /platform:iOS,/ && !/placeholder/ && !/Simulator/ { sub(/^.*id:/, ""); sub(/[,}].*$/, ""); print; exit }')"
  [[ -z "$device_id" ]] || destination="id=$device_id"
  echo "Refreshing BadgeAnimation signing for destination $destination."
  xcodebuild -quiet -project "$BADGE_PROJECT" -scheme BadgeAnimation -configuration Debug \
    -destination "$destination" -derivedDataPath "$BADGE_DERIVED_DATA" \
    -allowProvisioningUpdates CODE_SIGNING_ALLOWED=YES COMPILER_INDEX_STORE_ENABLE=NO clean build
  codesign --verify --deep --strict "$BADGE_APP"
  mkdir -p "$STATE_DIR"
  touch "$BADGE_PENDING_PATH"
  echo "BadgeAnimation signing refresh passed."
}

install_badge() {
  local device_id
  device_id="$(available_iphone_id)"
  if [[ -z "$device_id" ]]; then
    echo "BadgeAnimation install remains pending: no available iPhone."
    return 0
  fi
  xcrun devicectl device info ddiServices --device "$device_id" >/dev/null
  xcrun devicectl device install app --device "$device_id" "$BADGE_APP"
  rm -f "$BADGE_PENDING_PATH"
  if [[ "$AUTO_LAUNCH" == 1 ]]; then
    xcrun devicectl device process launch --device "$device_id" "$BADGE_BUNDLE_ID"
  fi
  echo "BadgeAnimation install completed."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) MODE=run ;;
    --auto-install) AUTO_INSTALL=1 ;;
    --auto-launch) AUTO_LAUNCH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --install-agent|--uninstall-agent) MODE="$1" ;;
    --status) MODE=status ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  --install-agent|--uninstall-agent)
    exec "$MUDSNOTE_REFRESH" "$MODE"
    ;;
  status)
    "$MUDSNOTE_REFRESH" --status || true
    if [[ -f "$BADGE_PENDING_PATH" ]]; then
      echo "A renewed BadgeAnimation build is waiting for installation."
    else
      echo "No BadgeAnimation install is pending."
    fi
    ;;
  run)
    if [[ "$DRY_RUN" == 1 ]]; then
      "$MUDSNOTE_REFRESH" --dry-run
      echo "Dry run: would inspect, refresh, and conditionally install BadgeAnimation."
      exit 0
    fi
    mudsnote_args=(--run)
    if [[ "$AUTO_INSTALL" == 1 ]]; then
      mudsnote_args+=(--auto-install)
      if [[ "$AUTO_LAUNCH" == 1 ]]; then
        mudsnote_args+=(--auto-launch)
      fi
    fi
    "$MUDSNOTE_REFRESH" "${mudsnote_args[@]}"
    if badge_requires_refresh; then
      refresh_badge
    else
      echo "BadgeAnimation signing remains outside the renewal threshold."
    fi
    if [[ "$AUTO_INSTALL" == 1 ]]; then
      [[ ! -f "$BADGE_PENDING_PATH" ]] || install_badge
    fi
    ;;
esac
