# Safe-area editor rhythm

## Baseline

- Started from `a3fac1b Make the library sidebar full height`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Anchored the editor stack to the editor pane safe area so full-size titlebar content cannot cover the date row.
- Reduced the editor title from 30pt to 24pt and tightened date-to-title spacing from 34pt to 8pt.
- Added a regression assertion for the safe-area top constraint.

## Verification

- Focused library-window tests passed.
- Installed visual QA confirmed the date row remains below the toolbar and the full-height sidebar still covers the traffic lights and sidebar controls.
- Final full-suite, packaging, signing, and installed-app checks are recorded in the completion commit.
