# 2026-07-12 Native inline folder editor

## Request

Determine whether Chinese input caused the default inline folder name not to be replaced, then continue the Apple Notes parity iteration.

## Baseline

- Branch: `main`
- HEAD: `42b227c`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- The inline folder editor was a standalone `NSTextView`, so it could not become an AppKit window field editor.

## Changes

- Replaced the source-list inline folder editor with a single-line `NSTextField`.
- Waits for `currentEditor()` before selecting the full default name and treating focus as established.
- Removed duplicate focus scheduling during source-row reconstruction and made repeated focus requests preserve the active field editor instead of ending its edit session.
- Routes Return, Escape, text changes, and focus-loss commit through `NSTextFieldDelegate`.
- Keeps the compact source-row geometry and existing create, rename, cancel, and error-recovery behavior.

## Verification

- Focused AppKit regression covers Chinese folder names plus create, rename, Return, and Escape behavior.
- Full Swift suite passed after the field-editor change.
- `/Applications/Mudsnote.app` was rebuilt and passed strict deep code-sign verification.
- Installed-app AX smoke confirmed the default name is selected in a live editable text field, ASCII input replaces it, a Chinese value commits with Return, and the resulting folder exists on disk.

## Decisions

- Use AppKit's shared field-editor contract for single-line source-list renaming.
- Chinese IME composition is a verification case, not a special alternate input path.

## Next

- Continue source-list visual comparison and deeper hierarchy tuning against Apple Notes.
