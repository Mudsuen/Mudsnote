#!/usr/bin/env bash
set -euo pipefail

# Refresh Xcode-managed iOS development signing on a logged-in Mac. This is an
# on-demand reinstall helper; it never stores an Apple credential in the
# repository or creates a periodic background job.

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

MODE="run"
AUTO_INSTALL=0
AUTO_LAUNCH=0
ALLOW_DEVICE_REGISTRATION=0
DRY_RUN=0

usage() {
  cat >&2 <<'EOF'
Usage:
  ./scripts/ios_signing_refresh.sh --run [--auto-install] [--auto-launch]
  ./scripts/ios_signing_refresh.sh --uninstall-agent
  ./scripts/ios_signing_refresh.sh --status
  ./scripts/ios_signing_refresh.sh --dry-run

Options:
  --auto-install                 Install the refreshed app on an available iPhone.
  --auto-launch                  Launch Mudsnote after an automatic install.
  --allow-device-registration   Let Xcode register a connected device if needed.
  --dry-run                     Print resolved paths and actions without building or changing launchd.

Legacy cleanup:
  --uninstall-agent               Remove a previously installed periodic agent.
  --status                        Report whether the legacy agent is still loaded.
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

release_lock() {
  if [[ -f "$LOCK_DIR/pid" ]]; then
    rm -f "$LOCK_DIR/pid"
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    trap release_lock EXIT
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
  trap release_lock EXIT
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
  log "Mode: on-demand; no periodic LaunchAgent will be created."
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

refresh_signing() {
  local -a provisioning_flags
  provisioning_flags=(-allowProvisioningUpdates)
  if [[ "$ALLOW_DEVICE_REGISTRATION" == "1" ]]; then
    provisioning_flags+=(-allowProvisioningDeviceRegistration)
  fi

  log "Refreshing Xcode-managed iOS signing."
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "${provisioning_flags[@]}" \
    CODE_SIGNING_ALLOWED=YES \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build

  if [[ ! -d "$APP_PATH" ]]; then
    log "Signed app was not produced at $APP_PATH"
    exit 1
  fi
  codesign --verify --deep --strict "$APP_PATH"

  local expiration
  expiration="$(profile_value "$APP_PATH/embedded.mobileprovision" ExpirationDate)"
  local ttl
  ttl="$(profile_value "$APP_PATH/embedded.mobileprovision" TimeToLive)"
  if [[ -n "$ttl" ]]; then
    log "Embedded development profile TTL: ${ttl} days."
  fi
  if [[ -n "$expiration" ]]; then
    log "Embedded development profile expiration: $expiration"
  else
    log "Embedded development profile expiration could not be read."
  fi
  log "Signing refresh build passed for $BUNDLE_ID."
}

install_on_available_iphone() {
  local device_id
  device_id="$(available_iphone_id)"
  if [[ -z "$device_id" ]]; then
    log "No available iPhone; signing refresh succeeded and install was skipped."
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
    log "iPhone DDI services are unavailable; install was skipped: $ddi_output"
    return 0
  fi
  if printf '%s\n' "$ddi_output" | grep -Eiq 'ddiServicesAvailable:[[:space:]]*false|device is locked|DeviceLocked'; then
    log "iPhone is locked or DDI services are unavailable; install was skipped."
    return 0
  fi

  log "Installing refreshed MudsnoteCompanion on iPhone $device_id."
  xcrun devicectl device install app --device "$device_id" "$APP_PATH"
  if [[ "$AUTO_LAUNCH" == "1" ]]; then
    log "Launching $BUNDLE_ID on iPhone $device_id."
    xcrun devicectl device process launch --device "$device_id" "$BUNDLE_ID"
  fi
  log "iPhone install completed."
}

run_refresh() {
  configure_logging
  acquire_lock
  resolve_paths
  print_configuration

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run: would run xcodebuild with -allowProvisioningUpdates."
    if [[ "$AUTO_INSTALL" == "1" ]]; then
      log "Dry run: would install on the first available iPhone."
    fi
    return 0
  fi

  refresh_signing
  if [[ "$AUTO_INSTALL" == "1" ]]; then
    install_on_available_iphone
  fi
}

install_agent() {
  log "Periodic LaunchAgent installation is disabled. Run --run --auto-install when reinstalling the iPhone app."
  exit 2
}

uninstall_agent() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  if [[ -f "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
    log "Removed $PLIST_PATH."
  else
    log "LaunchAgent plist was already absent: $PLIST_PATH"
  fi
}

show_status() {
  if launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null; then
    return 0
  fi
  log "LaunchAgent is not loaded: $LABEL"
  if [[ -f "$PLIST_PATH" ]]; then
    log "Plist exists but is not loaded: $PLIST_PATH"
  fi
  return 1
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
