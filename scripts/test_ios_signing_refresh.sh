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
[[ "$(plutil -extract ProgramArguments.2 raw -o - "$plist")" == "--auto-install" ]] \
  || fail "LaunchAgent must request a safe overwrite install"
[[ "$(plutil -extract ProgramArguments.3 raw -o - "$plist")" == "--auto-launch" ]] \
  || fail "LaunchAgent must request launch smoke after installation"
[[ "$(stat -f '%Lp' "$plist")" == "600" ]] \
  || fail "LaunchAgent plist must use least-privilege file permissions"

printf 'iOS signing refresh contract tests passed.\n'
