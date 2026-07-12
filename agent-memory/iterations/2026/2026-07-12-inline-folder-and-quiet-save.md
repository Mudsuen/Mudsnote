# 2026-07-12 Inline folder creation and quiet save

## Request

- Create folders by editing a new source-list row instead of opening an input dialog.
- Do not automatically reveal the saved note's file location.

## Baseline

- Branch: `main`
- HEAD observed before final verification: `6735c95`
- Dirty files before this iteration included the in-progress macOS main-menu shortcut work and an unrelated concurrent iOS UI-test change.

## Changes

- Added the Notes-style `Shift-Command-N` File-menu command.
- Replaced the new-folder alert with a temporary folder row using existing source-list geometry and a native folder symbol.
- Selected the default name on entry; Return commits, Escape cancels, and focus loss commits after the editor has received focus.
- Captured the parent directory when editing starts so later selection changes cannot redirect creation.
- Removed automatic Finder reveal from the save callback and removed its obsolete preference control. Explicit `在 Finder 中显示` actions remain available.
- Changed the legacy reveal preference default to false; the stored key remains compatibility-only and no longer drives save behavior.

## Verification

- Focused inline-folder, menu, settings, and settings-default tests passed.
- Full Swift suite passed before the final IME-focused installed-app probe and is rerun as the final gate.
- Production app installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- Isolated installed-app smoke kept one window, exposed the inline editor as focused `AXTextArea`, created the folder after IME composition was committed, and wrote a saved note while Mudsnote remained frontmost.
- Visual evidence: `/tmp/mudsnote-inline-folder-final.png`.

## Decisions

- New folder creation belongs in the source list, not a modal prompt.
- Normal save and autosave are quiet filesystem operations. Finder navigation is always explicit.
- IME composition is part of the native text-input contract: Return may first commit marked text before a later Return invokes folder creation.

## Next

- Continue Apple Notes parity work from `docs/apple-notes-parity-roadmap.md` without expanding the toolbar or window scale.
