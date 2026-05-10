# 2026-05-10 slash popover reference style

## Request

- The slash command popover still looked like it had an outer frame.
- Restyle it closer to the supplied command-menu reference.

## Baseline

- Branch: main
- HEAD: 536d4da
- Dirty files before work: none.

## Changes

- Kept the popover root border at zero.
- Changed the root background to a dark command-menu surface with no stroke.
- Added left-side SF Symbol icons for suggestion rows using each item's `symbolName`.
- Changed selected rows to a gray filled card with a subtle gray stroke instead of an accent-blue fill.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.
