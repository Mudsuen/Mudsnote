# 2026-07-10 library note list projection

## Request

Refactor every project under `/Users/Donald/Code` except Tauto, prioritizing performance, clearer code boundaries, and bug fixes while preserving existing behavior.

## Baseline

- Branch: `main`
- HEAD: `0bb9037`
- Dirty files before work: none

## Changes

- Extracted note-list sorting, pinned partitioning, date grouping, and row construction from `LibraryWindowController` into the pure `LibraryNoteListProjection` component.
- Standardized each note path once per projection instead of repeating URL standardization inside sort comparisons and pinned filters.
- Partitioned pinned and unpinned notes in one pass instead of filtering the complete list twice.
- Made Today/Yesterday grouping derive entirely from the supplied reference date so deterministic tests and preview snapshots do not accidentally consult wall-clock today.
- Added focused regression coverage for pinned, title-sorted, and date-grouped row ordering.

## Verification

- Commands run: `swift build`, `swift test`, `./scripts/package_app.sh`, packaged-app restart, `codesign --verify --deep --strict /Applications/Mudsnote.app`, `git diff --check`.
- App/page/package actually opened: `/Applications/Mudsnote.app` was replaced, restarted, and observed running from the installed bundle.
- Result: build passed; 107 tests passed; release package and strict signature verification passed.
- Not verified: no live editing or note-file mutation was scripted because this refactor only changes pure list projection.

## Decisions

- Keep AppKit selection, table reload, and persistence orchestration in `LibraryWindowController`; only deterministic row derivation belongs in the projection.
- Preserve Apple Notes-style group labels and existing pinned/search behavior.

## Next

- Continue splitting the library controller only along independently testable boundaries; avoid a broad controller rewrite.
