# 2026-07-02 - Attachment Context Actions

## Context

Local non-image attachment chips were visible and double-clickable. The remaining desktop interaction gap was that right-clicking a file chip still exposed only generic editor actions.

## Change

- Extended `MarkdownTextView` context-menu configuration to include the triggering event.
- Resolve local attachment paths from the right-click location.
- Add attachment-specific context actions in both library and floating editors:
  - Open Attachment
  - Reveal in Finder
  - Copy Attachment Path
- Preserve the existing floating-editor AI context menu after the attachment actions.
- Harden the visual QA script with a full-screen crop fallback when `screencapture -l` cannot capture the app window directly.

## Verification

- `swift test` passed with 80 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `git diff --check` passed.
- `./scripts/visual_notes_qa.sh` was not accepted as passed in the current desktop session: `screencapture -l` could not capture the window, full-screen capture produced blank content, Computer Use timed out, and later CoreGraphics did not expose an on-screen Mudsnote window. The script now detects blank screenshots instead of producing a false-positive comparison.
- iOS real-device validation was intentionally excluded from this macOS Notes-parity iteration.
