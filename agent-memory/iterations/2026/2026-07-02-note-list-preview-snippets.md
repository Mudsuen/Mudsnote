# 2026-07-02 note-list preview snippets

## Request

Continue the full Apple Notes parity goal for the macOS library UI and function.

## Baseline

- Branch: main
- HEAD: 2acbed6
- Dirty files before work: none

## Changes

- Added bounded preview hydration for recent-backed library rows.
- The normal note list now shows the first meaningful body line as a preview snippet.
- Kept source-list count refresh on the lightweight recent metadata path.
- Locked note-row title, snippet, and metadata labels to one line to prevent overlap.
- Added regression coverage for normal-list snippets and single-line row labels.

## Verification

- `swift test` passed with 65 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` with no arguments and showed `Mudsnote 笔记` at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-note-list-snippets-final.png`.

## Decisions

- Hydration is capped to the first 80 recent rows so the visible list gains Notes-like previews without restoring an unbounded launch-time scan.
- This slice stays within the existing local Markdown storage model; no cache or database was added.

## Next

- Continue visual tuning against the Apple Notes reference: source-list hierarchy, note-list background/row density, editor title/date spacing, and disabled toolbar states.
