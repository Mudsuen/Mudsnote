# 2026-07-09 editor body size

## Request

Continue the active Apple Notes parity goal after the source-list hierarchy pass, focusing next on the right-side editor's side-by-side readability.

## Baseline

- Branch: `main`
- HEAD before work: `0474d47 Strengthen Notes source list hierarchy`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-source-list-title-weight-final/apple-notes-vs-mudsnote.png`

## Changes

- Increased the Notes-like library editor body font from `16.5pt` to `17pt`.
- Increased the matching code font from `15.5pt` to `16pt`.
- Kept title size, date/title spacing, line spacing, paragraph spacing, editor inset, window size, toolbar scale, note loading, search, indexing, and Markdown serialization logic unchanged.
- Updated regression expectations for the editor typography contract.
- Updated the Apple Notes parity roadmap with the 17pt body reading size.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-body-size-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the editor body reads slightly stronger while the compact shell, toolbar scale, source list, and list column stay on the locked Notes-like baseline.

## Decisions

- Use a small body-size correction rather than re-enlarging the whole editor or shell, preserving the compact toolbar/window direction.
- Keep this pass presentation-only; no persistence, indexing, or rich text serialization behavior is changed.

## Next

- Continue with editor vertical rhythm or toolbar icon-state tuning after visual QA.
