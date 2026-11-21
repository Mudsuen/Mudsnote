#!/usr/bin/env bash
set -euo pipefail

# One entry point for refreshing and overwrite-installing the user's local iOS
# apps. Mudsnote retains the defensive profile recovery implementation in
# ios_signing_refresh.sh; the other apps are independent Xcode projects.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUDSNOTE_REFRESH="$ROOT_DIR/scripts/ios_signing_refresh.sh"
BADGE_ROOT="${BADGE_ANIMATION_ROOT:-/Users/Donald/Code/BadgeAnimation}"
BADGE_PROJECT="$BADGE_ROOT/BadgeAnimation.xcodeproj"
BADGE_DERIVED_DATA="$BADGE_ROOT/build/SigningRefreshDerivedData"
BADGE_APP="$BADGE_DERIVED_DATA/Build/Products/Debug-iphoneos/BadgeAnimation.app"
BADGE_BUNDLE_ID="com.codex.badgeanimation"
STATE_DIR="${MUDSNOTE_IOS_SIGNING_STATE_DIR:-${HOME:-/tmp}/Library/Application Support/Mudsnote}"
BADGE_PENDING_PATH="$STATE_DIR/badge-animation-signing-refresh-needs-install"
PROFILE_CACHE_DIR="${MUDSNOTE_IOS_PROFILE_CACHE_DIR:-${HOME:-/tmp}/Library/Developer/Xcode/UserData/Provisioning Profiles}"
PROFILE_BACKUP_DIR="${MUDSNOTE_IOS_PROFILE_BACKUP_DIR:-$STATE_DIR/signing-profile-backups}"
RENEWAL_THRESHOLD_SECONDS="${MUDSNOTE_IOS_SIGNING_RENEWAL_THRESHOLD_SECONDS:-432000}"

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

profile_matches_bundle() {
  local profile="$1" bundle_id="$2" app_id
  app_id="$(security cms -D -i "$profile" 2>/dev/null \
    | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null)" || return 1
  case "$app_id" in
    *."$bundle_id"|*."$bundle_id".*) return 0 ;;
  esac
  return 1
}

profile_requires_renewal() {
  local profile="$1" expiration now
  expiration="$(profile_expiration_epoch "$profile")" || return 0
  now="$(date '+%s')"
  (( expiration - now <= RENEWAL_THRESHOLD_SECONDS ))
}

isolate_app_profiles() {
  local bundle_id="$1" profile backup_path
  ISOLATED_APP_PROFILE_BACKUP=""
  [[ -d "$PROFILE_CACHE_DIR" ]] || return 0
  backup_path="$PROFILE_BACKUP_DIR/$(date -u '+%Y%m%dT%H%M%SZ')-$$-$bundle_id"
  while IFS= read -r -d '' profile; do
    if profile_matches_bundle "$profile" "$bundle_id" && profile_requires_renewal "$profile"; then
      if [[ -z "$ISOLATED_APP_PROFILE_BACKUP" ]]; then
        mkdir -p "$backup_path"
        ISOLATED_APP_PROFILE_BACKUP="$backup_path"
      fi
      mv "$profile" "$backup_path/"
    fi
  done < <(find "$PROFILE_CACHE_DIR" -maxdepth 1 -type f -name '*.mobileprovision' -print0)
}

restore_app_profiles() {
  local profile dest
  [[ -n "${ISOLATED_APP_PROFILE_BACKUP:-}" && -d "$ISOLATED_APP_PROFILE_BACKUP" ]] || return 0
  mkdir -p "$PROFILE_CACHE_DIR"
  while IFS= read -r -d '' profile; do
    dest="$PROFILE_CACHE_DIR/$(basename "$profile")"
    if [[ ! -e "$dest" ]]; then
      mv "$profile" "$dest"
    fi
  done < <(find "$ISOLATED_APP_PROFILE_BACKUP" -maxdepth 1 -type f -name '*.mobileprovision' -print0)
  rmdir "$ISOLATED_APP_PROFILE_BACKUP" 2>/dev/null || true
  ISOLATED_APP_PROFILE_BACKUP=""
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
  local name="$1" project="$2" scheme="$3" derived_data="$4" app="$5" pending="$6" bundle_id="$7" destination
  [[ -d "$project" ]] || { echo "$name project not found: $project" >&2; return 1; }
  destination="generic/platform=iOS"
  isolate_app_profiles "$bundle_id"
  echo "Refreshing $name signing for destination $destination."
  if ! xcodebuild -quiet -project "$project" -scheme "$scheme" -configuration Debug \
    -destination "$destination" -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates CODE_SIGNING_ALLOWED=YES COMPILER_INDEX_STORE_ENABLE=NO clean build; then
    restore_app_profiles
    return 1
  fi
  if ! codesign --verify --deep --strict "$app"; then
    restore_app_profiles
    return 1
  fi
  if app_requires_refresh "$app"; then
    restore_app_profiles
    echo "$name profiles were not renewed beyond the renewal threshold." >&2
    return 1
  fi
  mkdir -p "$STATE_DIR"
  touch "$pending"
  echo "$name signing refresh passed."
}

install_app() {
  local name="$1" app="$2" bundle_id="$3" pending="$4" device_id ddi_output launch_output
  device_id="$(available_iphone_id)"
  if [[ -z "$device_id" ]]; then
    echo "$name install remains pending: no available iPhone."
    return 0
  fi
  if ! ddi_output="$(xcrun devicectl device info ddiServices --device "$device_id" 2>&1)"; then
    echo "$name install remains pending: iPhone DDI services unavailable."
    return 0
  fi
  if printf '%s\n' "$ddi_output" | grep -Eiq 'ddiServicesAvailable:[[:space:]]*false|device is locked|DeviceLocked'; then
    echo "$name install remains pending: iPhone is locked or DDI services unavailable."
    return 0
  fi
  xcrun devicectl device install app --device "$device_id" "$app" || return 1
  rm -f "$pending"
  if [[ "$AUTO_LAUNCH" == 1 ]]; then
    if ! launch_output="$(xcrun devicectl device process launch --device "$device_id" "$bundle_id" 2>&1)"; then
      if printf '%s\n' "$launch_output" | grep -Eiq 'Locked|could not be unlocked'; then
        echo "$name install succeeded; launch deferred because the iPhone is locked."
      else
        printf '%s\n' "$launch_output" >&2
        return 1
      fi
    fi
  fi
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
    for pending in "$BADGE_PENDING_PATH"; do
      if [[ -f "$pending" ]]; then
        echo "A renewed local iOS build is waiting for installation: $pending"
      fi
    done
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
    # Each app has independent provisioning; one failure must not skip the others.
    result=0
    "$MUDSNOTE_REFRESH" "${mudsnote_args[@]}" || result=1

    badge_ready=1
    if app_requires_refresh "$BADGE_APP"; then
      refresh_app BadgeAnimation "$BADGE_PROJECT" BadgeAnimation "$BADGE_DERIVED_DATA" "$BADGE_APP" "$BADGE_PENDING_PATH" "$BADGE_BUNDLE_ID" || { badge_ready=0; result=1; }
    else
      echo "BadgeAnimation signing remains outside the renewal threshold."
    fi
    if [[ "$AUTO_INSTALL" == 1 && "$badge_ready" == 1 && -f "$BADGE_PENDING_PATH" ]]; then
      install_app BadgeAnimation "$BADGE_APP" "$BADGE_BUNDLE_ID" "$BADGE_PENDING_PATH" || result=1
    fi

    exit "$result"
    ;;
esac
