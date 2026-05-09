# 2026-05-09 compact slash command popover

## Request

- Make the slash-command list more compact.
- Make each command card smaller.

## Baseline

- Branch: main
- HEAD: 22a800b
- Dirty files before work: none.

## Changes

- Reduced suggestion popover width from 180 to 156.
- Reduced row height from 36 to 28.
- Reduced row title font from 13 to 12.
- Reduced row padding and corner radius.
- Added a regression test for the compact popover size.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.
