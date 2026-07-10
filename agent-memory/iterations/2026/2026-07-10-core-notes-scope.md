# 2026-07-10 core Notes scope

## Request

Continue aligning Mudsnote with Apple Notes while keeping architecture lightweight and fast. Treat non-core features such as call recordings and system sharing as optional rather than parity requirements.

## Baseline

- Branch: `main`
- HEAD before work: `ca86b80 Add Notes-style pinned notes`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-core-scope-20260710/apple-notes-vs-mudsnote.png` was generated after the change against `docs/visual-qa/apple-notes-reference.png`.

## Changes

- Removed the `Call Recordings` source row, scope state, search filter, count filter, empty state, symbol metric, and dedicated test.
- Removed system sharing from the toolbar menu, context menu, more menu, controller actions, and test surface.
- Preserved the compact `72x32` file-actions capsule and upload-arrow silhouette, but limited it to local Markdown copy/export plus the existing more menu.
- Kept multi-note copy/export, Finder reveal, move, delete, trash, pin, search, and editor behavior unchanged.
- Updated the Apple Notes parity roadmap and recorded the reduced non-core scope as a durable product decision.

## Verification

- Passed focused source-list, toolbar-state, copy/export, and trash lifecycle tests.
- Passed full `swift test`: 104 tests.
- Passed `git diff --check`.
- Passed `./scripts/package_app.sh`; installed `/Applications/Mudsnote.app`.
- Passed packaged-app visual QA at a canonical `1420x860` window:
  - comparison: `/tmp/mudsnote-visual-qa-core-scope-20260710/apple-notes-vs-mudsnote.png`
  - capture mode: direct window
  - frontmost app: Mudsnote
- Passed packaged-app accessibility smoke:
  - source list starts with `iCloud` / `All iCloud` and contains no call-recordings source.
  - file-actions capsule remains present with `复制与导出` and `更多` buttons.
  - copy/export menu contains only `复制 Markdown 内容` and `导出 Markdown...`.

## Decisions

- Apple Notes parity is scoped to the core local Markdown library and editor experience.
- Preserve reference-like toolbar geometry even when an Apple integration is omitted.
- Prefer deleting unused source/filter states over merely hiding their rows so count refresh and search code stay smaller.
- See `agent-memory/decisions/2026-07-10-core-notes-scope.md`.

## Next

- Continue with the largest visible library/editor delta from the canonical side-by-side comparison.
- Profile startup and large-library refresh paths before adding new metadata features.
