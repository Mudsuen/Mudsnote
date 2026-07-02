# 2026-07-02 library editor tools toolbar

## Request

Continue toward full Apple Notes parity for the macOS library while keeping Mudsnote local-first and lightweight.

## Baseline

- Branch: main
- HEAD: b5dbebf
- Dirty files before work: none

## Changes

- Added Notes-style editor toolbar items to the library window:
  - format menu
  - checklist
  - table
  - link
  - attachment
- Wired the library editor to real rich Markdown commands for inline formatting and checklist/list behavior instead of inert toolbar icons.
- Added Markdown-level table and link insertion.
- Added attachment insertion that copies files under the current note directory at `Attachments/yyyy/mm/` and inserts a standard relative Markdown link.
- Extended the library editor to interpret typed Markdown prefixes and keep structured newline/checklist behavior closer to the floating editor.
- Updated the Apple Notes parity roadmap's current gaps to reflect the new Markdown-level table/link/attachment support.

## Verification

- `swift test` passed with 64 tests.
- App regression coverage now verifies toolbar items and saved Markdown output for bold, checklist, table, link, and attachment insertion.
- `git diff --check` passed.
- XcodeBuildMCP `build_sim` passed for `MudsnoteCompanion` on the configured iPhone 17 simulator.
- `./scripts/device_smoke.sh` still reports `MudsPhone` as paired but unavailable to CoreDevice with local Xcode 26.5 / iPhoneOS SDK 26.5.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged smoke relaunched `/Applications/Mudsnote.app` with no arguments and showed `Mudsnote 笔记` at `1040x764`.
- Visual QA screenshot: `/tmp/mudsnote-window-library-editor-tools-toolbar-final.png`
- Visual follow-up: initial screenshot showed the search field had overflowed behind the toolbar chevron; this iteration then reduced search width and lowered file-action visibility priority so the search field remains visible.

## Decisions

- Keep attachment storage filesystem-backed and local to the note folder, using `Attachments/yyyy/mm/`.
- Keep table support as portable Markdown insertion for now; rich table cell editing and preview rendering remain future P2 work.
- Do not add decorative Apple Notes toolbar items unless they execute real local Markdown behavior.

## Next

- Run the remaining verification ladder.
- Continue P2 with richer table editing/attachment rendering and P3 search scope/highlight work.
