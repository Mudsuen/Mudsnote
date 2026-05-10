# 2026-05-10 opaque left aligned slash popover

## Request

- Do not use transparency in the slash command popover.
- Move text and row content closer to the left edge.

## Baseline

- Branch: main
- HEAD: e0040ef
- Dirty files before work: none.

## Changes

- Changed the slash popover root background to an opaque dark color.
- Changed selected-row background and stroke to opaque gray colors.
- Removed the table outer inset so rows begin at the popover edge.
- Reduced row icon and title leading padding.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.
