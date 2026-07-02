# 2026-07-02 dark note-list background

## Request

Continue the full Apple Notes parity goal for the macOS library UI.

## Baseline

- Branch: main
- HEAD: fc893fb
- Dirty files before work: none

## Changes

- Changed the middle note-list column to a darker background.
- Switched the `NSTableView` from source-list style to plain transparent style.
- Kept the custom Notes-like golden selected note card.
- Made the scroll view clip transparent so the list column no longer renders as a gray table block.

## Verification

- `swift test` passed with 65 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` with no arguments and showed `Mudsnote 笔记` at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-note-list-dark-background.png`.

## Decisions

- Kept the change visual-only; no storage, search, or editor behavior changed.
- Kept native table behavior and existing regression coverage while replacing the default source-list background.

## Next

- Continue with source-list hierarchy, editor title/date spacing, toolbar disabled states, and keyboard navigation.
