# Floating Window Manager Containment Design QA

## Evidence

- Source visual truth: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/codex-clipboard-48b2da31-235f-4cdd-a965-fc361de88581.png`.
- Rendered implementation: `/tmp/mudsnote-floating-contained-after-scroll.png`.
- Full-view manager comparison: `/tmp/mudsnote-floating-contained-full-comparison.png`.
- Focused row comparison: `/tmp/mudsnote-floating-contained-row-comparison.png`.
- Viewport: native macOS floating note at 412 x 314 points, with a 300 x 116 point borderless manager fully contained inside it. Automated coverage separately constrains the parent to 300 x 314 points, matching the user's narrow-window state.
- Pixels and density: source capture 678 x 356 pixels; implementation capture 830 x 628 pixels including the parent note and window shadow. The source and implementation manager regions were cropped to 600 x 232 pixels and compared at equal 2x density. Row regions were normalized to 568 x 66 pixels.
- State: dark appearance, one current unsaved floating note, manager open, empty focused search field.

## Full-view comparison evidence

- The manager retains the supplied title, new-window action, search field, divider, compact single-line record, subtitle, and close action.
- The implementation panel frame remains entirely inside the parent note frame. Its right edge no longer follows the inset anchor far enough to push the left edge outside a narrow parent.
- The red current-window marker is absent, while the row gains the released leading space without disturbing title, subtitle, or action alignment.
- Five downward wheel events over the one-row list produced byte-identical before/after screenshots (`b3cc32092917bf8df651ca9da342bacb9c14d6ee388288c5b57c0af4a38a1f43`), confirming no visible bounce or content movement.

## Focused region comparison evidence

- The focused equal-width row comparison makes the intended delta legible: the left-hand source includes the redundant red dot, while the right-hand implementation begins directly with the note title and preserves the same single-line rhythm.
- Native system fonts, vibrancy-aware colors, rounded geometry, and SF Symbol close action remain consistent with the existing app. No raster imagery, logos, illustrations, or generated assets are involved.
- Copy differs only because the isolated fixture is an unnamed note; control labels and meaning are unchanged.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the active implementation capture is lighter than the user's inactive/dimmed source capture because macOS vibrancy follows focus state; this is expected native behavior rather than token drift.

## Comparison history

### Pass 1

- The supplied source showed the manager extending left of the parent note, a red current-window dot, and a short list that reacted to wheel input.
- Fixes: clamp both axes to the parent frame, remove the current-window marker state, disable vertical elasticity without overflow, and reset the clip origin when scrolling becomes unnecessary.

### Pass 2

- Post-fix evidence: `/tmp/mudsnote-floating-contained-after-scroll.png`, `/tmp/mudsnote-floating-contained-full-comparison.png`, and `/tmp/mudsnote-floating-contained-row-comparison.png`.
- The manager is contained, the marker is gone, row alignment remains compact, and repeated wheel input leaves the one-row state unchanged. No actionable P0/P1/P2 differences remain.

## Implementation checklist

- [x] Keep the complete manager inside its parent note at narrow and default widths.
- [x] Remove the redundant current-window marker and state plumbing.
- [x] Disable both the scroller and elastic response for five or fewer rows.
- [x] Restore scrolling when results exceed five rows.
- [x] Reset the scroll offset when results shrink below the threshold.
- [x] Verify the rendered native state against the supplied screenshot.

final result: passed
