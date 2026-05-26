# 2026-05-25 floating note header content

## Request

Add more content to the Mudsnote floating note forehead/header and content area in the style of the provided screenshot, without keeping the short drag handle.

## Baseline

- Branch: main
- HEAD: 49b7a38
- Dirty files before work: pre-existing generated app icon assets, source icon SVG, and icon generation script.

## Changes

- Replaced the floating-note-only short drag handle with a header bar that shows the current note title and right-side icon actions for settings, search, and saving.
- Added an empty-body placeholder for the floating note content area.
- Kept the floating note header at a compact 28 pt height to match the feel of a standard macOS titlebar.
- Kept quick capture and normal saved-note editor chrome unchanged.
- Added a regression test for the floating note header, placeholder, and removal of the short handle.

## Verification

- Commands run:
  - `swift test`
  - `./scripts/package_app.sh`
  - `open -n -a /Applications/Mudsnote.app --args --floating-note`
  - `screencapture -x /tmp/mudsnote-floating-smoke.png`
- App/page/package actually opened: `/Applications/Mudsnote.app --args --floating-note`
- Result: tests passed, packaged app built, and screenshot showed the floating note with header icons and no short drag handle.
- Not verified: manual typing into the launched packaged panel was not performed.

## Decisions

- The new header is scoped to floating note mode only, because quick capture already has a separate title/body UI and normal editor windows still use the existing save-focused chrome.

## Next

- If the top-right plus should create a fresh separate draft instead of saving the current floating note, wire it through `AppController` as a dedicated action.
