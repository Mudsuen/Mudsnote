# 2026-07-02 note-list image thumbnails

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Dirty files before work: none after `80ad4c7`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: note-list rows still lacked thumbnail previews.

## Changes

- Added `thumbnailURL` to `NoteSearchResult`.
- Added local Markdown image reference parsing for:
  - `![alt](Attachments/image.png)`
  - normal Markdown links to local image files
  - percent-decoded relative paths
- Populated thumbnail URLs from list, search, trash, and recent-note paths that already load note Markdown.
- Added a 46px clipped thumbnail image view to library note rows.
- Image thumbnails replace the paperclip indicator; non-image attachments still use the paperclip.

## Verification

- Focused regression: `swift test --filter 'listNotesResolvesLocalImageThumbnailReferences|libraryNoteListShowsImageAttachmentThumbnail'` passed.
- `swift test` passed with 72 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-note-list-image-thumbnails-smoke.png`.

## Decisions

- Keep this local-only: remote images are ignored.
- Do not add a separate thumbnail cache or media index yet.
- Keep thumbnail extraction tied to already loaded Markdown bodies to preserve launch performance.

## Next

- Continue with exact row spacing, in-editor attachment previews, side-by-side visual QA, and search/index polish.
