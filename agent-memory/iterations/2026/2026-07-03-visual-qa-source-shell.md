# 2026-07-03 - Visual QA Source Shell

## Context

The visual QA side-by-side comparison was sometimes capturing the library while source folders and tags were still in deferred loading states. That made the Apple Notes comparison less useful because it showed transient loading rows instead of the steady sidebar.

## Change

- Source folder loading rows now stay hidden when the sidebar already has root folder rows to show.
- Tag indexing no longer shows transient `正在索引标签...` copy while tag discovery runs in the background.
- Empty tag copy can still appear after tags have actually loaded empty.
- Normal no-argument launches keep the existing shell-first deferred source loading behavior for startup performance.
- Updated `scripts/visual_notes_qa.sh` to explicitly launch the packaged library path.
- Added regression coverage for the quiet initial source shell and deferred tag/folder loading cleanup.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- Visual QA confirmed the source list no longer shows transient loading rows in the comparison screenshot.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.
