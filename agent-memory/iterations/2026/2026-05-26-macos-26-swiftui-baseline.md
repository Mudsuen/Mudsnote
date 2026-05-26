# 2026-05-26 macOS 26 SwiftUI baseline

## Request

Continue the cross-project modernization effort so app projects use the latest native SwiftUI framework and design, without preserving historical system compatibility.

## Baseline

- Branch: main
- HEAD: dd25f72
- Dirty files before work: clean

## Changes

- Raised the Swift tools declaration to 6.3.
- Raised the package platform baseline to macOS 26.
- Enabled Swift language mode v6 at the package level.
- Raised packaged app `LSMinimumSystemVersion` to `26.0`.

## Verification

- Commands run:
  - `swift build`
  - `swift test`
  - `./scripts/package_app.sh`
  - `plutil -p /Applications/Mudsnote.app/Contents/Info.plist`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app`
- Result:
  - Source build succeeded.
  - Test run passed with 53 tests.
  - Packaged app rebuilt and relaunched successfully.
  - Packaged app now declares `LSMinimumSystemVersion` as `26.0`.
- Not verified:
  - Manual quick-capture, search, and preferences interaction smoke is pending.

## Decisions

- For Mudsnote modernization, macOS 26 is the active baseline.
- Keep the current native utility-panel product direction while gradually moving app chrome and settings-like surfaces toward SwiftUI.

## Next

- Run the full test and packaging verification loop.
- Audit preferences and search windows as candidates for SwiftUI-first rewrites.
