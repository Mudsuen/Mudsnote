# 2026-07-11 Native main menu and new-note state

## Baseline

- Implemented on the macOS tree above `5286ed0`; concurrent iOS localization landed as `cc4bfda` and was left untouched.
- The status-item menu displayed `Command-N` beside quick capture, but the regular desktop app had no explicit Notes-like main menu contract.

## Implementation

- Added native Mudsnote, File, Edit, View, and Window menus with core commands only.
- Routed `Command-N` to the existing three-pane library and its in-place new-note action.
- Routed `Command-F` to the library search field and `Control-Command-S` to source-list visibility.
- Kept cut, copy, paste, select-all, undo, redo, close, minimize, and zoom on the AppKit responder chain.
- Removed the misleading `Command-N` label from the status-item quick-capture action; quick capture keeps its configurable global hotkey.
- Added explicit `isCreatingNewNote` state so an unsaved blank note hides the no-selection overlay, enables editing tools, shows the current date, and receives title focus after menu dismissal.

## Verification

- Added `applicationMainMenuProvidesNotesLikeCoreCommands` and strengthened toolbar-state coverage for a blank unsaved note.
- Focused menu and toolbar tests: 2 passed.
- Full Swift suite: 121 tests passed before the final conditional focus scheduling change; the complete suite was rerun afterward.
- Production package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- Isolated installed-app QA sent real `Command-N` through System Events: window count stayed `1`, dimensions stayed `1420x860`, and the focused accessibility role became `AXTextField`.
- Visual evidence: `/tmp/mudsnote-main-menu-qa-20260711/final-before-focus-fix.png` confirmed the blank editor uses a current-date header and no center empty-state overlay; focus was then verified through Accessibility after the scheduling fix.

## Lesson

- AppKit restores focus after menu tracking ends, so document actions that need a specific first responder should reassert focus on the next main-loop turn and guard that the document state is still current.
