# 2026-07-02 editor local image previews

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Previous commit: `f621813 Tighten note list density and launch shell first`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: local image references appeared as note-list thumbnails but not inside the editor.

## Changes

- Added a Markdown rich-text attribute to preserve original image Markdown on rendered attachments.
- Render local `![alt](path)` references as bounded inline `NSTextAttachment` previews when a current note URL is available.
- Resolve relative image paths against the current Markdown file directory.
- Keep unsupported, remote, or missing images on the existing plain Markdown/link rendering path.
- Passed the active note URL into library and standalone editor Markdown rendering.
- Added codec and library-window coverage for editor image preview rendering and Markdown round-trip serialization.

## Verification

- Focused regression: `swift test --filter 'richCodecRendersLocalMarkdownImagesAndSerializesPath|libraryNoteListShowsImageAttachmentThumbnail'` passed.
- Full regression: `swift test` passed with 73 tests.
- Packaging: `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Installed-app smoke: `open /Applications/Mudsnote.app` showed `Mudsnote 笔记` at `1040x764`.
- Screenshot: `/tmp/mudsnote-editor-local-image-previews-smoke.png`.

## Decisions

- Keep Markdown as the source of truth; image previews are render-time attachments only.
- Do not add an image index, cache, drag-resize handles, or broad non-image previews in this pass.
- Keep iOS real-device validation out of this goal; macOS installed-app smoke is the active artifact verification path.

## Next

- Continue with side-by-side visual QA, toolbar balance, broader keyboard navigation, and non-image attachment affordances.
