# 2026-07-02 - Non-image Attachment Previews

## Context

The desktop Apple Notes parity goal no longer includes iOS real-device installation or validation. This iteration continued the macOS library/editor parity work by closing part of the rich-editor attachment gap.

## Change

- Render existing non-image local Markdown links, such as PDFs stored under `Attachments/`, as visible attachment chips in the rich editor.
- Preserve the original Markdown link with `qmAttachmentMarkdown` so rich-text serialization remains lossless.
- Keep image references on the existing inline image path and leave remote/non-file links as ordinary links.
- Added regression coverage for local file attachment rendering and toolbar-inserted attachment references.

## Verification

- `swift test` passed with 80 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation was intentionally excluded from this macOS Notes-parity iteration.
