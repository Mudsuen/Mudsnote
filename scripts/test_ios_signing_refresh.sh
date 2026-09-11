#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/ios_signing_refresh.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_script_contract() {
  local pattern="$1"
  local description="$2"
  if ! grep -Eq "$pattern" "$SCRIPT"; then
    fail "$description"
  fi
}

assert_script_contract 'RENEWAL_THRESHOLD_SECONDS' \
  "signing refresh must check a renewal threshold before rebuilding"
assert_script_contract 'CHECK_INTERVAL_SECONDS' \
  "LaunchAgent must have an explicit bounded check interval"
assert_script_contract 'NEEDS_INSTALL_PATH' \
  "a skipped device install must remain pending for a later retry"
assert_script_contract 'ATTENTION_PATH' \
  "signing or account failures must remain visible until renewal succeeds"
assert_script_contract 'isolate_renewal_profiles' \
  "near-expiry Mudsnote profiles must be isolated before requesting renewal"
assert_script_contract 'restore_isolated_profiles' \
  "failed renewal must restore the previous cached profiles"
assert_script_contract 'available_xcode_iphone_id' \
  "renewal must prefer the connected iPhone over a generic destination"
assert_script_contract 'notify_failure' \
  "background failures must produce a user notification"
assert_script_contract 'redact_build_output' \
  "persisted build diagnostics must redact signing material"
assert_script_contract '^[[:space:]]*-quiet' \
  "background signing builds must suppress verbose identity output"
assert_script_contract 'chmod 600 "\$LOG_FILE"' \
  "the signing refresh log must be readable only by the signed-in user"

dry_run_output="$("$SCRIPT" --dry-run --auto-install --auto-launch)"
grep -Fq "would inspect the cached embedded profiles" <<<"$dry_run_output" \
  || fail "dry-run must describe threshold inspection"
grep -Fq "would isolate only near-expiry Mudsnote profiles" <<<"$dry_run_output" \
  || fail "dry-run must describe scoped profile isolation"
grep -Fq "would overwrite-install only after renewal or a pending retry" <<<"$dry_run_output" \
  || fail "dry-run must describe conditional overwrite installation"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/mudsnote-signing-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/home"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$test_root/bin/launchctl"
chmod +x "$test_root/bin/launchctl"

HOME="$test_root/home" \
PATH="$test_root/bin:$PATH" \
MUDSNOTE_IOS_SIGNING_LAUNCHCTL=launchctl \
  "$SCRIPT" --install-agent >/dev/null

plist="$test_root/home/Library/LaunchAgents/com.mudsnote.ios-signing-refresh.plist"
[[ -f "$plist" ]] || fail "install-agent must create a user LaunchAgent plist"
[[ "$(plutil -extract StartInterval raw -o - "$plist")" == "21600" ]] \
  || fail "LaunchAgent must check at the configured six-hour interval"
[[ "$(plutil -extract RunAtLoad raw -o - "$plist")" == "true" ]] \
  || fail "LaunchAgent must check once after login/load"
[[ "$(plutil -extract ProgramArguments.0 raw -o - "$plist")" == "$ROOT_DIR/scripts/ios_apps_signing_refresh.sh" ]] \
  || fail "LaunchAgent must use the unified iOS app signing entry point"
[[ "$(plutil -extract ProgramArguments.2 raw -o - "$plist")" == "--auto-install" ]] \
  || fail "LaunchAgent must request a safe overwrite install"
[[ "$(plutil -extract ProgramArguments.3 raw -o - "$plist")" == "--auto-launch" ]] \
  || fail "LaunchAgent must request launch smoke after installation"
[[ "$(stat -f '%Lp' "$plist")" == "600" ]] \
  || fail "LaunchAgent plist must use least-privilege file permissions"

# Exercise the actual functions against synthetic tools and state only.
sed '/^while \[\[ \$# -gt 0 \]\]; do/,$d' "$SCRIPT" > "$test_root/functions.sh"
(
  source "$test_root/functions.sh"
  PROJECT=synthetic
  ATTENTION_PATH="$test_root/attention"
  fixture=""
  xcodebuild() { printf '%s\n' "$fixture"; }
  fixture='Available destinations for the "Test" scheme:
{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
Ineligible destinations for the "Test" scheme:
{ platform:iOS, id:unavailable-phone, name:iPhone, error:Locked }'
  [[ -z "$(available_xcode_iphone_id)" ]] || fail "placeholder and ineligible devices must use the generic fallback"
  fixture='Available destinations for the "Test" scheme:
{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
{ platform:iOS Simulator, id:simulator, name:iPhone }
{ platform:iOS, arch:arm64, id:real-phone, name:Test phone }'
  [[ "$(available_xcode_iphone_id)" == real-phone ]] || fail "must select a concrete available iOS device"

  cat > "$test_root/bin/notify" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
  chmod +x "$test_root/bin/notify"
  # Capture notification arguments without launching AppleScript.
  OSASCRIPT_BIN="$test_root/bin/notify"
  FAILURE_REASON=signing-build-failed
  # Override the stub with a private output file, never the real notification tool.
  printf '\nprintf "%%s\n" "$@" > "%s"\n' "$test_root/notification" >> "$OSASCRIPT_BIN"
  notify_failure
  ! grep -q 'Sign in in Xcode' "$test_root/notification" || fail "build errors must not request reauthentication"
  FAILURE_REASON=xcode-account-authentication
  notify_failure
  grep -q 'Sign in in Xcode' "$test_root/notification" || fail "authentication errors must explain recovery"

  configure_logging() { :; }
  acquire_lock() { :; }
  resolve_paths() { :; }
  print_configuration() { :; }
  signing_refresh_required() { return 0; }
  refresh_signing() { touch "$test_root/refreshed"; }
  printf '2026-09-08T00:00:00Z\txcode-account-authentication\n' > "$ATTENTION_PATH"
  AUTO_INSTALL=1
  run_refresh
  [[ ! -e "$test_root/refreshed" ]] || fail "background auth failures must wait for manual recovery"
  AUTO_INSTALL=0
  run_refresh
  [[ -e "$test_root/refreshed" ]] || fail "manual refresh must be able to recover from an auth failure"
)

printf 'iOS signing refresh contract tests passed.\n'
