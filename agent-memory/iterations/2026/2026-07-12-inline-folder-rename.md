# 2026-07-12 Inline folder rename

## Request

Continue Apple Notes UI and workflow parity while keeping the desktop shell compact and the implementation efficient.

## Baseline

- Branch: `main`
- HEAD: `9ece582`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- New-folder naming was already inline, but the folder context-menu rename action still used `NSAlert`.

## Changes

- Replaced the create-only folder edit variables with one `InlineFolderEditOperation` state machine.
- Reused the same source-row editor for create and rename instead of maintaining parallel focus and keyboard paths.
- During rename, the normal row is replaced at the same hierarchy depth and stack position.
- Captured the target URL at edit start; commit renames that exact folder even if other selection state changes.
- Return and focus loss commit, Escape cancels, and failures restore the attempted value in the inline editor before showing the error.
- Routed the existing folder context-menu Rename command directly into inline editing.

## Verification

- Focused AppKit regression covers context-menu action dispatch, row replacement, default-name selection state, rename commit, and cancellation.
- Production package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- Isolated installed-app Accessibility smoke opened the real context menu, confirmed one window and a focused `AXTextArea`, committed `Rename Seed` to `Renamed Final`, then verified a second rename was cancelled with Escape.
- Filesystem verification confirmed the old path disappeared after commit and no cancelled path was created.
- Visual evidence: `/tmp/mudsnote-inline-rename-final.png`.

## Decisions

- Folder creation and rename share one inline editing primitive.
- Context-menu rename should not open a modal or temporarily navigate the note list to another folder.

## Next

- Continue P1/P4 parity with keyboard and focus-state audits, then return to remaining visible hierarchy tuning.
