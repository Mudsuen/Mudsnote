# Higher Editor Content Origin

## Context

The clear Apple Notes crop showed the note title higher than Mudsnote after the date-to-title spacing had already been tightened.

## Change

- Reduced `LibraryNotesLayout.editorTopInset` from `18pt` to `12pt`.
- Kept the `20pt` date row, `8pt` date-to-title spacing, and `8pt` title-to-body spacing unchanged.
- Updated the exact layout regression assertion.

## Verification

- Focused library-window layout test passed.
- Full `swift test` passed.
- Packaged `/Applications/Mudsnote.app` passed strict code-sign verification.
- Side-by-side capture confirmed the whole editor content origin moved upward by `6pt` without clipping or changing horizontal reading edges.

## Follow-up

Continue geometry work from the packaged-app capture rather than compounding changes to the already calibrated date-to-title gap.
