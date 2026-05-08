# 2026-05-08 floating save and format shortcuts

## Request

- In the floating note, `cmd+s` should not act as Save.
- Verify and list the available formatting keyboard shortcuts.

## Baseline

- Branch: main
- HEAD: 5614d3d
- Dirty files before work: none.

## Changes

- Removed the hard-coded `cmd+s` save routing from `QuickEntryPanel`.
- Kept note saving behind the configured Save note shortcut, which defaults to `cmd+return`.
- Added missing formatting shortcuts for underline and strikethrough:
  - `cmd+u` for underline
  - `cmd+shift+x` for strikethrough
- Replaced numeric key-code literals in formatting shortcut routing with Carbon key-code constants.

## Verified Shortcuts

- `cmd+b`: bold
- `cmd+i`: italic
- `cmd+u`: underline
- `cmd+shift+x`: strikethrough
- `cmd+option+1`: heading
- `cmd+shift+7`: numbered list
- `cmd+shift+8`: bulleted list
- `cmd+shift+9`: checklist
- `cmd+return`: configured Save note default
- `cmd+s`: not Save unless the user explicitly sets Save note to `command+s`

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.
