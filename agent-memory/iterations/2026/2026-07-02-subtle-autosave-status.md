# 2026-07-02 subtle autosave status

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Previous commit: `11aa1d4 Autosave library editor changes`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: library autosave existed, but the dirty-state copy still felt like a manual-save editor.

## Changes

- Replaced the library editor's persistent `已修改` dirty label with `正在保存...` for existing notes.
- New unsaved library notes now show `新笔记，正在保存...` while autosave is pending.
- Existing autosave completion still returns the centered metadata line to the normal date text.
- Tightened autosave regression coverage to assert the transient save-progress state.

## Verification

- Focused regression: `swift test --filter 'libraryWindowAutosavesEditedExistingNote'` passed.
- Full regression: `swift test` passed with 75 tests.
- Packaging: `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Installed-app smoke: `open /Applications/Mudsnote.app` showed `Mudsnote 笔记` at `1040x764`.
- Screenshot: `/tmp/mudsnote-subtle-autosave-status-smoke.png`.

## Decisions

- Keep the centered metadata line lightweight; do not add a separate save badge or progress spinner.
- Keep iOS real-device validation out of this goal; macOS installed-app smoke is the active artifact verification path.

## Next

- Continue with editor title/body spacing, source-list spacing, toolbar balance, and visual QA.
