# Reference-Aligned Collapsed Toolbar

## Request

Continue Apple Notes UI parity after aligning the expanded library toolbar.

## Baseline

- Branch: `main`
- HEAD: `46dc4f2`
- Pre-existing dirty files: iOS companion work only; untouched by this iteration.

## Changes

- Set the collapsed list-title leading offset to `-58pt` while retaining `0pt` in expanded state.
- Wrapped only the collapsed `30pt` Sidebar Toggle glass surface in a `34pt` trailing-aligned wrapper.
- Kept the expanded toggle implementation and source controls unchanged.

## Verification

- Focused library-window test passed.
- Full `swift test` passed.
- `git diff --check` passed.
- Repackaged and launched `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Stable compact comparison: `/tmp/mudsnote-collapsed-toolbar-175/apple-notes-vs-mudsnote.png`.
- The collapsed toggle center is within about `2pt` and the title origin within about `2.5pt` of the checked-in reference.

## Decisions

- Use original cropped images or a `292pt` comparison target while checking compact states; viewing a still-being-written large comparison can look partially blank.
- Keep expanded and collapsed toolbar alignment state-specific instead of changing shared widths.

## Next

- Continue parity work from stable state-matched captures, prioritizing remaining visible differences over color-only tuning.
