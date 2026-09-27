#!/usr/bin/env bash
set -euo pipefail

# One entry point for refreshing and overwrite-installing the user's local iOS
# apps. Mudsnote retains the defensive profile recovery implementation in
# ios_signing_refresh.sh; the other apps are independent Xcode projects.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUDSNOTE_REFRESH="$ROOT_DIR/scripts/ios_signing_refresh.sh"
BADGE_ROOT="${BADGE_ANIMATION_ROOT:-/Users/Donald/Documents/Codex/2026-08-25/jl/work/ios-badge-animation}"
BADGE_PROJECT="$BADGE_ROOT/BadgeAnimation.xcodeproj"
BADGE_DERIVED_DATA="$BADGE_ROOT/build/SigningRefreshDerivedData"
BADGE_APP="$BADGE_DERIVED_DATA/Build/Products/Debug-iphoneos/BadgeAnimation.app"
BADGE_BUNDLE_ID="com.codex.badgeanimation"
SHORTCUT_ROOT="${SHORTCUT_TILES_ROOT:-}"
SHORTCUT_PROJECT="$SHORTCUT_ROOT/ShortcutTiles.xcodeproj"
SHORTCUT_DERIVED_DATA="$SHORTCUT_ROOT/build/SigningRefreshDerivedData"
SHORTCUT_APP="$SHORTCUT_DERIVED_DATA/Build/Products/Debug-iphoneos/ShortcutTiles.app"
SHORTCUT_BUNDLE_ID="com.donald.ShortcutTiles"
STATE_DIR="${MUDSNOTE_IOS_SIGNING_STATE_DIR:-${HOME:-/tmp}/Library/Application Support/Mudsnote}"
BADGE_PENDING_PATH="$STATE_DIR/badge-animation-signing-refresh-needs-install"
SHORTCUT_PENDING_PATH="$STATE_DIR/shortcut-tiles-signing-refresh-needs-install"
RENEWAL_THRESHOLD_SECONDS="${MUDSNOTE_IOS_SIGNING_RENEWAL_THRESHOLD_SECONDS:-172800}"

AUTO_INSTALL=0
AUTO_LAUNCH=0
DRY_RUN=0
MODE=run

profile_expiration_epoch() {
  local profile="$1" expiration
  [[ -f "$profile" ]] || return 1
  expiration="$(security cms -D -i "$profile" 2>/dev/null \
    | plutil -extract ExpirationDate raw -o - - 2>/dev/null)" || return 1
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s' 2>/dev/null
}

app_requires_refresh() {
  local app="$1" profile expiration now found=0
  [[ -d "$app" ]] || return 0
  now="$(date '+%s')"
  while IFS= read -r -d '' profile; do
    found=1
    expiration="$(profile_expiration_epoch "$profile")" || return 0
    if (( expiration - now <= RENEWAL_THRESHOLD_SECONDS )); then
      return 0
    fi
  done < <(find "$app" -name embedded.mobileprovision -print0)
  [[ "$found" == 1 ]] || return 0
  return 1
}

available_iphone_id() {
  xcrun devicectl list devices 2>&1 \
    | awk 'NR > 2 && /iPhone/ && ($4 == "connected" || $4 == "available") { print $3; exit }'
}


refresh_app() {
  local name="$1" project="$2" scheme="$3" derived_data="$4" app="$5" pending="$6" destination
  [[ -d "$project" ]] || { echo "$name project not found: $project" >&2; return 1; }
  destination="generic/platform=iOS"
  echo "Refreshing $name signing for destination $destination."
  xcodebuild -quiet -project "$project" -scheme "$scheme" -configuration Debug \
    -destination "$destination" -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates CODE_SIGNING_ALLOWED=YES COMPILER_INDEX_STORE_ENABLE=NO clean build || return 1
  codesign --verify --deep --strict "$app" || return 1
  if app_requires_refresh "$app"; then
    echo "$name profiles were not renewed beyond the renewal threshold." >&2
    return 1
  fi
  mkdir -p "$STATE_DIR"
  touch "$pending"
  echo "$name signing refresh passed."
}

install_app() {
  local name="$1" app="$2" bundle_id="$3" pending="$4" device_id
  device_id="$(available_iphone_id)"
  if [[ -z "$device_id" ]]; then
    echo "$name install remains pending: no available iPhone."
    return 0
  fi
  xcrun devicectl device info ddiServices --device "$device_id" >/dev/null || return 1
  xcrun devicectl device install app --device "$device_id" "$app" || return 1
  if [[ "$AUTO_LAUNCH" == 1 ]]; then
    xcrun devicectl device process launch --device "$device_id" "$bundle_id" || return 1
  fi
  rm -f "$pending"
  echo "$name install completed."
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
    for pending in "$BADGE_PENDING_PATH" "$SHORTCUT_PENDING_PATH"; do
      if [[ -f "$pending" ]]; then
        echo "A renewed local iOS build is waiting for installation: $pending"
      fi
    done
    ;;
  run)
    if [[ "$DRY_RUN" == 1 ]]; then
      "$MUDSNOTE_REFRESH" --dry-run
      echo "Dry run: would inspect, refresh, and conditionally install BadgeAnimation (and ShortcutTiles only when SHORTCUT_TILES_ROOT is configured)."
      exit 0
    fi
    mudsnote_args=(--run)
    if [[ "$AUTO_INSTALL" == 1 ]]; then
      mudsnote_args+=(--auto-install)
      if [[ "$AUTO_LAUNCH" == 1 ]]; then
        mudsnote_args+=(--auto-launch)
      fi
    fi
    # Each app has independent provisioning; one failure must not skip the others.
    result=0
    "$MUDSNOTE_REFRESH" "${mudsnote_args[@]}" || result=1

    badge_ready=1
    if app_requires_refresh "$BADGE_APP"; then
      refresh_app BadgeAnimation "$BADGE_PROJECT" BadgeAnimation "$BADGE_DERIVED_DATA" "$BADGE_APP" "$BADGE_PENDING_PATH" || { badge_ready=0; result=1; }
    else
      echo "BadgeAnimation signing remains outside the renewal threshold."
    fi
    if [[ "$AUTO_INSTALL" == 1 && "$badge_ready" == 1 && -f "$BADGE_PENDING_PATH" ]]; then
      install_app BadgeAnimation "$BADGE_APP" "$BADGE_BUNDLE_ID" "$BADGE_PENDING_PATH" || result=1
    fi

    if [[ -n "$SHORTCUT_ROOT" ]]; then
      shortcut_ready=1
      if app_requires_refresh "$SHORTCUT_APP"; then
        refresh_app ShortcutTiles "$SHORTCUT_PROJECT" ShortcutTiles "$SHORTCUT_DERIVED_DATA" "$SHORTCUT_APP" "$SHORTCUT_PENDING_PATH" || { shortcut_ready=0; result=1; }
      fi
      if [[ "$AUTO_INSTALL" == 1 && "$shortcut_ready" == 1 && -f "$SHORTCUT_PENDING_PATH" ]]; then
        install_app ShortcutTiles "$SHORTCUT_APP" "$SHORTCUT_BUNDLE_ID" "$SHORTCUT_PENDING_PATH" || result=1
      fi
    fi
    exit "$result"
    ;;
esac
