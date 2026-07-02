# 2026-07-02 editor vertical rhythm

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Previous commit: `818bfa4 Soften library autosave status copy`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: the right editor pane still needed exact title/body vertical spacing and side-by-side visual tuning.

## Changes

- Increased the library note title font from 28pt to 30pt.
- Reduced the editor body text top inset from 8pt to 4pt.
- Changed editor side margins from 30pt to 44pt.
- Replaced uniform editor stack spacing with explicit 24pt date-to-title and 6pt title-to-body spacing.
- Added identifiers and regression coverage for the editor layout contract.

## Verification

- Focused regression: `swift test --filter 'libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'` passed.
- Full regression: `swift test` passed with 75 tests.
- Packaging: `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Installed-app smoke: `open /Applications/Mudsnote.app` showed `Mudsnote 笔记` at `1040x764`.
- Screenshot: `/tmp/mudsnote-editor-vertical-rhythm-smoke.png`.

## Decisions

- Keep this as a layout contract change only; do not redesign the editor component hierarchy.
- Keep iOS real-device validation out of this goal; macOS installed-app smoke is the active artifact verification path.

## Next

- Continue with side-by-side visual QA, source-list spacing, and toolbar balance.
