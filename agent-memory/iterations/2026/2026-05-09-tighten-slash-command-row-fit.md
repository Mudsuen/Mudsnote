# 2026-05-09 tighten slash command row fit

## Request

- Make the slash command popover frame and option rows fit more tightly.
- Reduce extra space below the text inside selected rows.

## Baseline

- Branch: main
- HEAD: 4e2dd3e
- Dirty files before work: none.

## Changes

- Reduced popover outer inset from 4 to 2.
- Reduced slash suggestion row height from 28 to 24.
- Reduced max popover height from 148 to 124 for five visible rows.
- Moved selected-row highlight into a tighter inner selection view.
- Centered row text with a slight upward offset to reduce the perceived bottom gap.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.
