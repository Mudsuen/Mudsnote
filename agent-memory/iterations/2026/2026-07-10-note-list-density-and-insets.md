# Note List Density And Insets

## Scope

- Baseline: `f81c6da Tune Notes middle toolbar buttons`
- Keep source-list, scrolling, loading, search, selection, and editor behavior unchanged.
- Match the Apple Notes reference's middle-column vertical rhythm and card/text geometry.

## Evidence

- Same-height navigation crops showed Mudsnote fitting more note content vertically than the reference.
- Mudsnote note text sat about half as far from the selected-card leading edge as Apple Notes.
- The selected card left too little breathing room before the scrollbar.

## Implementation

- Increased recency-group rows from `48pt` to `56pt` and note rows from `96pt` to `108pt`.
- Increased note text leading inset to `46pt` and aligned separators to the same inset.
- Added asymmetric selection/hover geometry with a larger trailing inset and `10pt` continuous-looking corner radius.

## Verification

- Four targeted layout, scrolling, keyboard-navigation, and sorting/grouping tests passed.
- Full `swift test` passed: 102 tests in 2 suites.
- `git diff --check` passed.
- `./scripts/package_app.sh` installed the packaged build at `/Applications/Mudsnote.app`.
- Same-height navigation crops confirmed the selected-card height and text-to-card leading distance now closely track the Apple Notes reference, while cumulative recency-group spacing is substantially closer.
- Final comparison: `/tmp/mudsnote-visual-qa-note-list-density-20260710/apple-notes-vs-mudsnote.png`.
