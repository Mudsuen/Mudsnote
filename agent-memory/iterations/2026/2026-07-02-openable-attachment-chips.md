# 2026-07-02 - Openable Attachment Chips

## Context

The previous iteration made non-image local Markdown attachments visible in the rich editor. Apple Notes-style attachment parity also requires the visible file block to behave like a usable file affordance.

## Change

- Store the resolved local file path on rendered attachment chips with `qmAttachmentFilePath`.
- Show a pointing-hand cursor when hovering a local attachment chip.
- Open the local attachment with the system workspace on double-click in both the library editor and floating editor.
- Keep serialization tied to the original Markdown link so storage remains local-first and lossless.

## Verification

- `swift test` passed with 80 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation was intentionally excluded from this macOS Notes-parity iteration.
