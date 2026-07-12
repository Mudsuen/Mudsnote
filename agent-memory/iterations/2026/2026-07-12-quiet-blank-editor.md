# 2026-07-12 Quiet blank editor

## Request

Continue visual and functional Apple Notes parity without changing the accepted compact window and toolbar scale.

## Baseline

- Branch: `main`
- HEAD: `8586fab`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- The canonical empty-note comparison still showed `Select or create a note` in Mudsnote's editor while Apple Notes kept the same state blank.

## Changes

- Removed the editor-only empty placeholder view from the hierarchy.
- Removed its visibility updates from initial loading, reloads, new-note entry, search/navigation, note loading, typing, saving, and document removal.
- Kept note-list empty and no-results states unchanged because those are actionable list feedback, not editor instructions.

## Verification

- Focused empty-Markdown and toolbar-state tests passed.
- Production package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- The canonical visual harness was rerun with the same empty fixture and viewport.
- Side-by-side evidence confirms the Mudsnote editor now shows only the date and blank canvas, matching the Apple Notes reference state.
- Visual evidence: `/tmp/mudsnote-visual-qa-quiet-editor/apple-notes-vs-mudsnote.png` and `/tmp/mudsnote-visual-qa-quiet-editor/mudsnote-library.png`.

## Decisions

- The editor canvas does not show instructional empty-state copy.
- List-level empty/no-result feedback remains because it describes navigation results rather than editing behavior.

## Next

- Continue from the remaining complex-content and hierarchy tuning gaps in `docs/apple-notes-parity-roadmap.md`.
