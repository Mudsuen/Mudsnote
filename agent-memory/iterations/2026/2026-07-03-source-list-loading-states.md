# 2026-07-03 - Source-list Loading States

## Context

The Notes-like source list already deferred full folder loading and tag indexing to keep the library shell responsive. The visual gap was that these sections could appear blank or unfinished while async work was pending.

## Change

- Added quiet status rows for source-list folder and tag sections.
- Folder section now shows `正在载入文件夹...` until full folder rows are loaded.
- Tag section now shows `正在索引标签...` until tag rows are available, and can show `没有标签` after an empty tag load.
- Status rows are plain labels, not selectable source rows, so source button tags, counts, folder movement, and selection logic remain unchanged.
- Added regression coverage for initial loading copy and cleanup after folder/tag rows load.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.
