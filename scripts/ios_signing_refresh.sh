#!/usr/bin/env bash
set -euo pipefail

# Refresh Xcode-managed iOS development signing on a logged-in Mac. The
# optional user LaunchAgent checks the cached profiles before expiry and never
# stores an Apple credential in the repository, plist, state, or logs.

LABEL="com.mudsnote.ios-signing-refresh"
PROJECT_RELATIVE_PATH="iOS/MudsnoteCompanion.xcodeproj"
SCHEME="MudsnoteCompanion"
BUNDLE_ID="app.mudsnote.companion"
CONFIGURATION="${MUDSNOTE_IOS_SIGNING_CONFIGURATION:-Debug}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${MUDSNOTE_IOS_SIGNING_DERIVED_DATA_PATH:-$ROOT_DIR/build/IOSAutoSigningRefreshDerivedData}"
LOG_DIR="${MUDSNOTE_IOS_SIGNING_LOG_DIR:-${HOME:-/tmp}/Library/Logs/Mudsnote}"
LOG_FILE="$LOG_DIR/ios-signing-refresh.log"
LOCK_DIR="${TMPDIR:-/tmp}/mudsnote-ios-signing-refresh.lock"
PLIST_PATH="${HOME:-/tmp}/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="${MUDSNOTE_IOS_SIGNING_STATE_DIR:-${HOME:-/tmp}/Library/Application Support/Mudsnote}"
NEEDS_INSTALL_PATH="$STATE_DIR/ios-signing-refresh-needs-install"
LAST_SUCCESS_PATH="$STATE_DIR/ios-signing-refresh-last-success"
RENEWAL_THRESHOLD_SECONDS="${MUDSNOTE_IOS_SIGNING_RENEWAL_THRESHOLD_SECONDS:-172800}"
CHECK_INTERVAL_SECONDS="${MUDSNOTE_IOS_SIGNING_CHECK_INTERVAL_SECONDS:-21600}"
LAUNCHCTL_BIN="${MUDSNOTE_IOS_SIGNING_LAUNCHCTL:-launchctl}"
OSASCRIPT_BIN="${MUDSNOTE_IOS_SIGNING_OSASCRIPT:-osascript}"

MODE="run"
AUTO_INSTALL=0
AUTO_LAUNCH=0
ALLOW_DEVICE_REGISTRATION=0
DRY_RUN=0
BUILD_OUTPUT_PATH=""

usage() {
  cat >&2 <<'EOF'
Usage:
  ./scripts/ios_signing_refresh.sh --run [--auto-install] [--auto-launch]
  ./scripts/ios_signing_refresh.sh --install-agent
  ./scripts/ios_signing_refresh.sh --uninstall-agent
  ./scripts/ios_signing_refresh.sh --status
  ./scripts/ios_signing_refresh.sh --dry-run

Options:
  --auto-install                 Install the refreshed app on an available iPhone.
  --auto-launch                  Launch Mudsnote after an automatic install.
  --allow-device-registration   Let Xcode register a connected device if needed.
  --dry-run                     Print resolved paths and actions without building or changing launchd.
  --install-agent               Install/load the periodic user LaunchAgent.
  --uninstall-agent             Remove the periodic user LaunchAgent.
  --status                      Report the agent and pending-install state.
EOF
}

log() {
  local message="$1"
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S%z')] $message"
  printf '%s\n' "$line"
}

configure_logging() {
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  mkdir -p "$LOG_DIR"
  if [[ -t 1 ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    exec >> "$LOG_FILE" 2>&1
  fi
}

notify_failure() {
  if ! command -v "$OSASCRIPT_BIN" >/dev/null 2>&1; then
    return
  fi
  "$OSASCRIPT_BIN" -e \
    'display notification "Automatic renewal needs attention. Check the redacted Mudsnote log." with title "Mudsnote signing refresh failed"' \
    >/dev/null 2>&1 || true
}

cleanup() {
  local status="$?"
  if [[ -n "$BUILD_OUTPUT_PATH" && -f "$BUILD_OUTPUT_PATH" ]]; then
    rm -f "$BUILD_OUTPUT_PATH"
  fi
  if [[ -f "$LOCK_DIR/pid" ]]; then
    rm -f "$LOCK_DIR/pid"
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if [[ "$status" != "0" && "$DRY_RUN" != "1" && "$MODE" == "run" ]]; then
    notify_failure
  fi
  exit "$status"
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    trap cleanup EXIT
    return
  fi

  local existing_pid=""
  if [[ -f "$LOCK_DIR/pid" ]]; then
    existing_pid="$(<"$LOCK_DIR/pid")"
  fi
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    log "Another signing refresh is already running (pid $existing_pid); skipping."
    exit 0
  fi

  # A stale lock can only name this narrow, task-owned directory. Remove its
  # marker and retry once so a killed LaunchAgent cannot disable future runs.
  rm -f "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Could not acquire the signing refresh lock; skipping."
    exit 0
  fi
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  trap cleanup EXIT
}

resolve_paths() {
  PROJECT="$ROOT_DIR/$PROJECT_RELATIVE_PATH"
  APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/MudsnoteCompanion.app"
  if [[ ! -d "$PROJECT" ]]; then
    log "iOS project not found: $PROJECT"
    exit 1
  fi
}

profile_value() {
  local profile_path="$1"
  local key_path="$2"
  if [[ ! -f "$profile_path" ]]; then
    return 0
  fi
  security cms -D -i "$profile_path" 2>/dev/null \
    | plutil -extract "$key_path" raw -o - - 2>/dev/null \
    || true
}

print_configuration() {
  log "Repository: $ROOT_DIR"
  log "Project: $PROJECT"
  log "Scheme/configuration: $SCHEME / $CONFIGURATION"
  log "Derived data: $DERIVED_DATA_PATH"
  log "Renewal threshold: $RENEWAL_THRESHOLD_SECONDS seconds."
  log "Periodic check interval: $CHECK_INTERVAL_SECONDS seconds."
  log "Automatic device registration: $ALLOW_DEVICE_REGISTRATION"
  log "Automatic install: $AUTO_INSTALL"
  log "Automatic launch: $AUTO_LAUNCH"
}

available_iphone_id() {
  local device_list
  device_list="$(xcrun devicectl list devices 2>&1 || true)"
  printf '%s\n' "$device_list" \
    | awk 'NR > 2 && /iPhone/ && ($4 == "connected" || $4 == "available") { print $3; exit }'
}

iphone_state_summary() {
  local device_list
  device_list="$(xcrun devicectl list devices 2>&1 || true)"
  printf '%s\n' "$device_list" \
    | awk 'NR > 2 && /iPhone/ { print; }'
}

profile_expiration_epoch() {
  local profile_path="$1"
  local expiration
  expiration="$(profile_value "$profile_path" ExpirationDate)"
  if [[ -z "$expiration" ]]; then
    return 1
  fi
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s' 2>/dev/null
}

profile_requires_renewal() {
  local profile_path="$1"
  local expiration_epoch now_epoch remaining
  if [[ ! -f "$profile_path" ]]; then
    return 0
  fi
  if ! expiration_epoch="$(profile_expiration_epoch "$profile_path")"; then
    return 0
  fi
  now_epoch="$(date '+%s')"
  remaining=$((expiration_epoch - now_epoch))
  (( remaining <= RENEWAL_THRESHOLD_SECONDS ))
}

signing_refresh_required() {
  local widget_profile
  widget_profile="$APP_PATH/PlugIns/MudsnoteCompanionWidget.appex/embedded.mobileprovision"
  if [[ ! -d "$APP_PATH" ]]; then
    return 0
  fi
  if profile_requires_renewal "$APP_PATH/embedded.mobileprovision"; then
    return 0
  fi
  if profile_requires_renewal "$widget_profile"; then
    return 0
  fi
  return 1
}

redact_build_output() {
  sed -E \
    -e 's/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/<redacted-email>/g' \
    -e 's/[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}/<redacted-uuid>/g' \
    -e 's/[[:xdigit:]]{40,64}/<redacted-hash>/g' \
    -e 's/(Signing Identity:).*/\1 <redacted>/' \
    -e 's/(Provisioning Profile:).*/\1 <redacted>/' \
    -e 's/(certificate[^:]*:).*/\1 <redacted>/I'
}

refresh_signing() {
  local -a provisioning_flags
  provisioning_flags=(-allowProvisioningUpdates)
  if [[ "$ALLOW_DEVICE_REGISTRATION" == "1" ]]; then
    provisioning_flags+=(-allowProvisioningDeviceRegistration)
  fi

  log "Refreshing Xcode-managed iOS signing."
  BUILD_OUTPUT_PATH="$(mktemp "${TMPDIR:-/tmp}/mudsnote-ios-signing-build.XXXXXX")"
  if ! xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "${provisioning_flags[@]}" \
    CODE_SIGNING_ALLOWED=YES \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build >"$BUILD_OUTPUT_PATH" 2>&1; then
    log "Xcode signing refresh failed. Redacted diagnostic tail follows."
    tail -n 40 "$BUILD_OUTPUT_PATH" | redact_build_output
    return 1
  fi

  if [[ ! -d "$APP_PATH" ]]; then
    log "Signed app was not produced at $APP_PATH"
    exit 1
  fi
  codesign --verify --deep --strict "$APP_PATH"

  local expiration widget_expiration
  expiration="$(profile_value "$APP_PATH/embedded.mobileprovision" ExpirationDate)"
  widget_expiration="$(profile_value "$APP_PATH/PlugIns/MudsnoteCompanionWidget.appex/embedded.mobileprovision" ExpirationDate)"
  if [[ -z "$expiration" || -z "$widget_expiration" ]]; then
    log "Embedded development profile expiration could not be read for every signed bundle."
    return 1
  fi
  if profile_requires_renewal "$APP_PATH/embedded.mobileprovision" \
    || profile_requires_renewal "$APP_PATH/PlugIns/MudsnoteCompanionWidget.appex/embedded.mobileprovision"; then
    log "Xcode did not produce profiles beyond the configured renewal threshold."
    return 1
  fi
  mkdir -p "$STATE_DIR"
  touch "$NEEDS_INSTALL_PATH"
  log "Signing refresh passed for $BUNDLE_ID."
  log "Main profile expiration: $expiration"
  log "Widget profile expiration: $widget_expiration"
}

install_on_available_iphone() {
  local device_id
  device_id="$(available_iphone_id)"
  if [[ -z "$device_id" ]]; then
    log "No available iPhone; overwrite install remains pending for the next scheduled check."
    local states
    states="$(iphone_state_summary)"
    if [[ -n "$states" ]]; then
      log "Known iPhone state: $states"
    fi
    return 0
  fi

  log "Checking Developer Disk Image services for iPhone $device_id."
  local ddi_output
  if ! ddi_output="$(xcrun devicectl device info ddiServices --device "$device_id" 2>&1)"; then
    log "iPhone DDI services are unavailable; overwrite install remains pending for the next scheduled check."
    return 0
  fi
  if printf '%s\n' "$ddi_output" | grep -Eiq 'ddiServicesAvailable:[[:space:]]*false|device is locked|DeviceLocked'; then
    log "iPhone is locked or DDI services are unavailable; overwrite install remains pending."
    return 0
  fi

  log "Installing refreshed MudsnoteCompanion on iPhone $device_id."
  local install_output
  if ! install_output="$(xcrun devicectl device install app --device "$device_id" "$APP_PATH" 2>&1)"; then
    log "Overwrite install failed; it remains pending for the next scheduled check."
    printf '%s\n' "$install_output" | tail -n 24 | redact_build_output
    return 1
  fi
  rm -f "$NEEDS_INSTALL_PATH"
  mkdir -p "$STATE_DIR"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$LAST_SUCCESS_PATH"
  if [[ "$AUTO_LAUNCH" == "1" ]]; then
    log "Launching $BUNDLE_ID on iPhone $device_id."
    local launch_output
    if ! launch_output="$(xcrun devicectl device process launch --device "$device_id" "$BUNDLE_ID" 2>&1)"; then
      if printf '%s\n' "$launch_output" | grep -Eiq 'Locked|could not be unlocked'; then
        log "Overwrite install succeeded; launch was deferred because the iPhone is locked."
      else
        log "Overwrite install succeeded, but launch smoke failed."
        printf '%s\n' "$launch_output" | tail -n 24 | redact_build_output
        return 1
      fi
    fi
  fi
  log "iPhone install completed."
}

run_refresh() {
  configure_logging
  acquire_lock
  resolve_paths
  print_configuration

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run: would inspect the cached embedded profiles against the renewal threshold."
    log "Dry run: would rebuild with -allowProvisioningUpdates only when renewal is due."
    if [[ "$AUTO_INSTALL" == "1" ]]; then
      log "Dry run: would overwrite-install only after renewal or a pending retry."
    fi
    return 0
  fi

  local renewed=0
  if signing_refresh_required; then
    log "Cached signing is missing or within the renewal threshold."
    refresh_signing
    renewed=1
  else
    log "Cached signing remains outside the renewal threshold; rebuild skipped."
  fi
  if [[ "$AUTO_INSTALL" == "1" && ( "$renewed" == "1" || -f "$NEEDS_INSTALL_PATH" ) ]]; then
    install_on_available_iphone
  elif [[ "$AUTO_INSTALL" == "1" ]]; then
    log "No renewal or pending retry; overwrite install skipped."
  fi
}

write_agent_plist() {
  local plist_dir temp_plist
  plist_dir="$(dirname "$PLIST_PATH")"
  mkdir -p "$plist_dir" "$LOG_DIR"
  temp_plist="$(mktemp "${TMPDIR:-/tmp}/mudsnote-ios-signing-refresh.plist.XXXXXX")"
  trap 'rm -f "$temp_plist"' RETURN

  plutil -create xml1 "$temp_plist"
  plutil -insert Label -string "$LABEL" "$temp_plist"
  plutil -insert ProgramArguments -xml '<array/>' "$temp_plist"
  plutil -insert ProgramArguments.0 -string "$ROOT_DIR/scripts/ios_signing_refresh.sh" "$temp_plist"
  plutil -insert ProgramArguments.1 -string '--run' "$temp_plist"
  plutil -insert ProgramArguments.2 -string '--auto-install' "$temp_plist"
  plutil -insert ProgramArguments.3 -string '--auto-launch' "$temp_plist"
  plutil -insert StartInterval -integer "$CHECK_INTERVAL_SECONDS" "$temp_plist"
  plutil -insert RunAtLoad -bool true "$temp_plist"
  plutil -insert ThrottleInterval -integer 300 "$temp_plist"
  plutil -insert WorkingDirectory -string "$ROOT_DIR" "$temp_plist"
  plutil -insert StandardOutPath -string "$LOG_FILE" "$temp_plist"
  plutil -insert StandardErrorPath -string "$LOG_FILE" "$temp_plist"
  plutil -insert ProcessType -string Background "$temp_plist"
  plutil -insert EnvironmentVariables -xml \
    '<dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin</string></dict>' \
    "$temp_plist"
  plutil -lint "$temp_plist" >/dev/null
  mv "$temp_plist" "$PLIST_PATH"
  chmod 600 "$PLIST_PATH"
  trap - RETURN
}

install_agent() {
  if [[ "$(id -u)" == "0" ]]; then
    log "Run --install-agent as the signed-in desktop user, not root."
    exit 2
  fi
  if ! "$LAUNCHCTL_BIN" print "gui/$(id -u)" >/dev/null 2>&1; then
    log "The current GUI launchd domain is unavailable; sign in to macOS and retry."
    exit 2
  fi
  resolve_paths
  write_agent_plist
  "$LAUNCHCTL_BIN" bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  "$LAUNCHCTL_BIN" bootstrap "gui/$(id -u)" "$PLIST_PATH"
  log "Installed and loaded $PLIST_PATH."
  log "It checks every $CHECK_INTERVAL_SECONDS seconds and renews within $RENEWAL_THRESHOLD_SECONDS seconds of expiry."
}

uninstall_agent() {
  "$LAUNCHCTL_BIN" bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  if [[ -f "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
    log "Removed $PLIST_PATH."
  else
    log "LaunchAgent plist was already absent: $PLIST_PATH"
  fi
}

show_status() {
  local status=0
  if ! "$LAUNCHCTL_BIN" print "gui/$(id -u)/$LABEL"; then
    log "LaunchAgent is not loaded: $LABEL"
    status=1
  fi
  if [[ ! -f "$PLIST_PATH" ]]; then
    log "LaunchAgent plist is absent: $PLIST_PATH"
    status=1
  elif [[ "$status" != "0" ]]; then
    log "Plist exists but is not loaded: $PLIST_PATH"
  fi
  if [[ -f "$NEEDS_INSTALL_PATH" ]]; then
    log "A renewed build is waiting for a safe overwrite install."
  else
    log "No overwrite install is pending."
  fi
  return "$status"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      MODE="run"
      ;;
    --install-agent)
      MODE="install-agent"
      ;;
    --uninstall-agent)
      MODE="uninstall-agent"
      ;;
    --status)
      MODE="status"
      ;;
    --auto-install)
      AUTO_INSTALL=1
      ;;
    --auto-launch)
      AUTO_LAUNCH=1
      ;;
    --allow-device-registration)
      ALLOW_DEVICE_REGISTRATION=1
      ;;
    --dry-run)
      DRY_RUN=1
      MODE="run"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

case "$MODE" in
  run)
    run_refresh
    ;;
  install-agent)
    install_agent
    ;;
  uninstall-agent)
    uninstall_agent
    ;;
  status)
    show_status
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 2
    ;;
esac
