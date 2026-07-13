# 2026-07-13 incremental folder-tree projection

## Request

Continue Apple Notes UI parity while making Mudsnote navigation architecture and performance as efficient as practical.

## Baseline

- Branch: `main`
- Starting HEAD: `b85522d`
- Dirty files before work: concurrent iOS companion files, left untouched

## Changes

- Added `LibraryFolderTreeProjection` for sorted insertion, subtree rename remapping, and subtree removal within the existing three-level source hierarchy.
- Switched folder create, rename, and delete commands from recursive main-thread discovery to immediate mutation of the loaded tree snapshot.
- Updated only the affected parent child flag instead of rebuilding metadata for every row.
- Added a folder-load generation guard so an older deferred scan cannot overwrite a newer local lifecycle result.

## Verification

- Snapshot-isolation coverage proves create, rename, and delete do not synchronously discover an unrelated external folder.
- Existing nested-folder, disclosure, inline rename, move, and lifecycle tests pass.
- The first 10,000-row projection measured about `126ms` total test time and failed the `<50ms` operation gate.
- Boundary-standardized raw-path comparisons reduced stable total test time to `38–40ms`; the measured insertion passes `<50ms`.
- Full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- `./scripts/library_smoke.sh /tmp/mudsnote-library-smoke-folder-projection-204` passed, including folder move and attachment reload.
- `codesign --verify --deep --strict /Applications/Mudsnote.app` passed.
- Expanded content-state visual comparison passed at `/tmp/mudsnote-visual-qa-204-folder-projection/apple-notes-vs-mudsnote.png`.

## Decisions

- Treat the loaded source hierarchy as authoritative for direct local commands; let the filesystem monitor reconcile external changes asynchronously.
- Normalize mutation arguments once, then compare stored raw paths in large loops.
- Preserve the existing maximum source depth so incremental and background projections cannot diverge.

## Next

- Continue complex editor-content parity and audit remaining synchronous metadata reads after file lifecycle commands.
