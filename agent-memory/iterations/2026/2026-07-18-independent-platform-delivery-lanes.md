# Independent platform delivery lanes

## Scope contract

Every implementation task declares one of:

- `macos`: macOS SwiftPM tests, package, `/Applications/Mudsnote.app`.
- `ios`: iOS Xcode tests, build, connected-iPhone install.
- `both`: explicitly requested cross-platform work only.

## Commands

- `scripts/verify macos pr|full|live`
- `scripts/verify ios pr|full|live`
- `scripts/verify both pr|full|live`

Devflow may call the legacy one-argument PR/full form; platform detection delegates it safely. Live never auto-detects because installation must name its target.

## Isolation

The macOS lane never invokes Xcode or the device installer. The iOS lane never invokes SwiftPM macOS builds or `package_app.sh`. Only explicit `both` composes the two lanes.
