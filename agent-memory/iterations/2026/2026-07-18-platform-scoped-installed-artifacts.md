# Platform-scoped installed artifacts

## Root cause

Git worktrees isolate source and `dist/build`, but all Mudsnote worktrees install macOS builds to `/Applications/Mudsnote.app`. An iOS-only task packaged its branch's older macOS source and overwrote the current mac artifact.

## Rule

- macOS work may run `scripts/package_app.sh` and `scripts/verify live`.
- iOS-only work may run shared non-installing tests and the iOS Xcode/device flow, but must not mutate `/Applications/Mudsnote.app`.

## Guard

`package_app.sh` refuses branches whose changes relative to `main` are limited to `iOS/` and documentation. The explicit `MUDSNOTE_ALLOW_IOS_ONLY_MAC_INSTALL=1` override is only for a deliberate macOS baseline smoke.
