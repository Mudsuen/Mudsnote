# Folder disclosure accessibility

## Request

Continue Apple Notes parity with native hierarchy behavior.

## Baseline

- Branch: `main`
- HEAD: `09e4559`
- Dirty files before work: none

## Changes

- Folder disclosure buttons now name the folder and whether activation will expand or collapse it.
- Added regression checks across collapsed, expanded, and restored disclosure states.

## Verification

- Focused nested-folder test passed.
- `swift test` and `git diff --check` passed.
- Packaged, strictly signature-verified, and launched `/Applications/Mudsnote.app`.
- Visual QA: `/tmp/mudsnote-folder-disclosure-a11y-180/apple-notes-vs-mudsnote.png`; no visible regression.

## Decisions

- Derive disclosure semantics from the same persisted state used to choose the chevron symbol.

## Next

- Continue P4 native state and accessibility verification.
