# 2026-07-02 Markdown export action

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Dirty files before work: none after `94e281c`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: toolbar still needed a share/export affordance.

## Changes

- Added a `square.and.arrow.up` toolbar item labeled `导出 Markdown`.
- Added `导出 Markdown...` to the note context menu and more-actions menu.
- Export saves pending edits first, then copies the selected source `.md` file to the requested destination.
- Export is enabled for normal selected notes and disabled for empty libraries and Recently Deleted.
- Kept export local-first and plain Markdown-only.

## Verification

- Focused regression: `swift test --filter 'libraryToolbarUsesNotesLikeDisabledStates|libraryWindowDeletesRestoresAndPermanentlyDeletesNotes|libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'` passed.
- `swift test` passed with 70 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-markdown-export-smoke.png`.

## Decisions

- Use direct Markdown file copy instead of a proprietary export pipeline.
- Keep Apple/iCloud share services out of scope until explicitly requested.
- Save pending edits before copying so the exported file matches the visible editor state.

## Next

- Continue with richer export destinations, side-by-side visual QA, note-list row spacing, and attachment previews.
