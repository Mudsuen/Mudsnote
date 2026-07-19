# 2026-07-19 macOS title Return to body

## Request

In the macOS library editor, Return in the title should continue to the body instead of selecting the whole title.

## Scope

- Platform: macOS only.
- Surface: three-pane library title and body editor.
- Out of scope: iOS, quick capture, editor layout, and persistence semantics.

## Change

- Handle `insertNewline(_:)` from the library `titleField` delegate after native IME handling.
- Move focus to `editorTextView` and place its insertion point at the first body line.
- Preserve the title and any existing body content.
- Exercise the same Return path in both the AppKit regression and installed library smoke.

## Verification

- Focused regression: `libraryTitleReturnMovesToStartOfBodyWithoutSelectingTitle`.
- Required full suite, packaging, Devflow PR verification, and installed-app smoke are recorded in the task delivery evidence.
