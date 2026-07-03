# 2026-07-03 - Attachment Metadata And Markdown Copy

## Context

Local non-image attachment chips were visible, double-clickable, and had file context actions. The next parity gap was making each chip identify the file more clearly and keeping the portable Markdown reference available from the file affordance itself.

## Change

- Show deterministic file metadata in the attachment chip secondary line, for example `PDF · 3 bytes`.
- Store the metadata on the rendered attachment with `qmAttachmentMetadata` for tests and future UI reuse.
- Keep the original Markdown link on the rendered attachment and expose it through the attachment context menu.
- Add a `MarkdownAttachmentReference` object so editor context menus can use path, markdown, and metadata together without reparsing the note.
- Expanded regression coverage for attachment metadata and the copy-Markdown-link menu item.

## Verification

- `swift test` passed with 80 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `git diff --check` passed.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`; visual comparison remains useful for later shell tuning.
- iOS real-device validation was intentionally excluded from this macOS Notes-parity iteration.
