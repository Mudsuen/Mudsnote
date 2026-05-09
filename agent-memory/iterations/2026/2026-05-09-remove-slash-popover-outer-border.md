# 2026-05-09 remove slash popover outer border

## Request

- Remove the slash command popover's outer frame.
- Keep a stroke on the selected option card edge.

## Baseline

- Branch: main
- HEAD: 6a84eee
- Dirty files before work: none.

## Changes

- Removed the root slash suggestion popover border.
- Kept the selected row's inner card border.
- Added a regression assertion that the popover root border width stays zero.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.
