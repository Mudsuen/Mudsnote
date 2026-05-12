# 2026-05-12 standard settings review

## Request

- Change Settings to a more standard macOS format.
- Add the Settings items that should exist now.
- Review the project concretely and fix bugs found in that pass.

## Baseline

- Branch: main
- HEAD: 7cd4969
- Dirty files before work: none.

## Changes

- Replaced the visible Settings tab strip with a macOS preference-style toolbar and no-border content panes.
- Removed the placeholder planning section and added real persisted options:
  - reveal saved notes in Finder,
  - keep the floating note above other windows,
  - check spelling while typing.
- Reused an already-open Settings window instead of recreating it, so in-progress Settings edits are not discarded by repeated `cmd+,` or menu opens.
- Kept the Settings window fully opaque when panel opacity is previewed.
- Rejected duplicate shortcut assignments before saving so global hotkeys and editor save routing do not compete for the same key gesture.
- Renamed the status menu entry and hotkey error wording from Preferences to Settings.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- `open -na /Applications/Mudsnote.app --args --preferences`
- Confirmed packaged app process running as `/Applications/Mudsnote.app/Contents/MacOS/Mudsnote --preferences`.

## Decisions

- Added only Settings items backed by live app behavior instead of adding disabled placeholders.
- Kept the existing explicit Save/Cancel workflow for shortcut validation while moving the window chrome and navigation toward standard macOS Settings.
