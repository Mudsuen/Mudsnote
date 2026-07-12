# 2026-07-12 Notes-style link sheet

## Request

Continue desktop Apple Notes UI and core-workflow parity while preserving local-first Markdown and compact toolbar geometry.

## Baseline

- Branch: `main`
- HEAD: `2228566`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- Link insertion and editing used application-modal `NSAlert.runModal()` prompts and editing could change only the URL.

## Changes

- Captured the real Apple Notes Add Link state before implementation: window-attached sheet, Link To and Name fields, destination-gated OK, Cancel, and focused destination input.
- Added a shared `LinkEditorSheetController` used by the library and floating editor.
- Matched the reference information hierarchy with a centered title, stacked labels, tall destination field, optional name field, and trailing Cancel/OK buttons.
- Selected editor text becomes the default link name; empty names fall back to the destination.
- Existing links can update both visible labels and destinations while preserving Markdown round-trip and floating-editor undo/redo.
- Return submits, Escape cancels, and dismissal returns focus to the editor.

## Verification

- Focused tests cover destination validation, submit/cancel lifecycle, label and URL edits, remove-link behavior, and undo/redo.
- Side-by-side screenshots compared the Apple Notes reference sheet and the installed Mudsnote sheet in the same empty-destination state.
- Installed-app smoke selected `Selected text`, submitted `https://example.com`, returned to one editor window, and persisted `[Selected text](https://example.com)` to disk.
- Full Swift suite passed after the final layout adjustment.
- Final package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.

## Decisions

- Use a window-modal sheet, not an application-modal alert or transient popover.
- Keep link UI shared across editor surfaces and Markdown as the authoritative persistence format.

## Next

- Continue complex editor-content visual tuning and attachment preview parity.
