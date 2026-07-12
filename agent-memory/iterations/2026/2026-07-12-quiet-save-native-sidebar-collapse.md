# Quiet save and native sidebar collapse

## Baseline

- Started from `7296734 Align editor content with the safe area`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Left the editor date unchanged while autosave is pending and refreshed it from the saved file modification date after success.
- Added a 0.22-second native split-item animation for user-triggered sidebar collapse.
- Hid Add Folder and changed the sidebar toggle to a bordered circular control in collapsed mode.
- Removed the nonessential right-side share/export and more toolbar group.
- Unified mouse and keyboard toolbar-menu anchors.
- Darkened the native rounded sidebar and made visual QA prefer a physical external display.

## Verification

- Focused shell and autosave tests passed.
- Installed expanded and collapsed captures were taken on the external MSI display.
- The expanded comparison confirmed the darker rounded sidebar; the collapsed capture confirmed the state-specific toolbar and leftmost note-list layout.
- Final full-suite, packaging, signing, and installed-app checks are recorded in the completion commit.
