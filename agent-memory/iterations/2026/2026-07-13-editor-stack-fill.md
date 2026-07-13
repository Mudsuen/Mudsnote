# Editor stack fill

## Context

- Started from `34d2a30`.
- The supplied Apple Notes crop showed the note title directly below the centered date, while Mudsnote could leave a large flexible gap.

## Change

- Set `LibraryEditorStack.distribution` to `.fill`.
- Added a layout assertion so the top rhythm cannot silently return to AppKit's gravity-area distribution.

## Verification

- Focused test: `swift test --filter libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`.
- Packaged and strictly verified `/Applications/Mudsnote.app`.
- Comparison: `/tmp/mudsnote-editor-stack-fill-177/apple-notes-vs-mudsnote.png`.

## Decision

- Keep the existing `12pt` editor top inset, `20pt` date row, and `8pt` date-to-title spacing. The visible defect came from stack distribution, not those measured constants.
