# 2026-07-02 note-list row density

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Dirty files before work: none after `d849a38`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: note-list rows still needed exact spacing and density polish.
- Startup gap found during smoke: direct `/Applications/Mudsnote.app` launch could expose a zero-size library window when initial preview hydration ran before the shell was visible.

## Changes

- Reduced normal note row height from 72 to 68.
- Tightened note-row vertical padding.
- Reduced title font from 14 to 13.5.
- Reduced selected-card inset/radius for a tighter Apple Notes-like card.
- Reduced image thumbnails from 46px to 44px.
- Made the app launch path regular instead of accessory when the library should open.
- Added a deferrable initial hydration path so installed-app direct launch shows the three-pane library shell before loading previews and the selected note.
- Removed `LSUIElement` from the packaged app and refreshed LaunchServices registration during packaging so direct bundle opening follows the normal windowed app path.
- Added tests for row height, title font, and thumbnail dimensions.

## Verification

- Focused regression: `swift test --filter 'defaultLaunchOpensLibraryUnlessAnotherSurfaceIsRequested|libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|libraryNoteListShowsImageAttachmentThumbnail'` passed.
- Full regression: `swift test` passed with 72 tests.
- Packaging: `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Installed-app smoke: `open /Applications/Mudsnote.app` showed `Mudsnote 笔记` at `1040x764`, not a zero-size window.
- Screenshot: `/tmp/mudsnote-note-list-row-density-smoke.png`.

## Decisions

- Keep the density tune scoped to row metrics; do not redesign the note row data model.
- Preserve single-line title/snippet/meta truncation so narrow windows remain stable.
- Keep iOS real-device validation out of this goal; macOS installed-app smoke is the active artifact verification path.

## Next

- Continue with in-editor attachment previews, side-by-side visual QA, search/index polish, and broader keyboard navigation.
