# 2026-07-02 library editor autosave

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Previous commit: `886bbef Expand search result keyboard stepping`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: the library editor still exposed a manual dirty state after edits instead of saving like Apple Notes.

## Changes

- Added a debounced autosave timer to the library window controller.
- Editable library-note changes schedule autosave after a short delay.
- Explicit save and close paths invalidate the timer and still flush pending changes.
- Recently Deleted remains read-only and does not autosave.
- Added regression coverage that an edited existing library note is written back automatically.

## Verification

- Focused regression: `swift test --filter 'libraryWindowAutosavesEditedExistingNote|libraryWindowEditorToolbarInsertsRichMarkdownTools'` passed.
- Full regression: `swift test` passed with 75 tests.
- Packaging: `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Installed-app smoke: `open /Applications/Mudsnote.app` showed `Mudsnote 笔记` at `1040x764`.
- Screenshot: `/tmp/mudsnote-library-editor-autosave-smoke.png`.

## Decisions

- Keep autosave local and debounce-based; do not introduce a database, background index, or sync layer.
- Leave quick capture as explicit save/draft behavior.
- Keep iOS real-device validation out of this goal; macOS installed-app smoke is the active artifact verification path.

## Next

- Continue with save-state copy polish, editor spacing, source-list spacing, and visual QA.
