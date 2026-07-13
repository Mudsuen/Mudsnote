# Snapshot folder disclosure

## Request

Continue Apple Notes UI parity while keeping the library architecture lightweight and responsive.

## Baseline

- Branch: `main`
- HEAD: `49c2f31`
- Dirty files before work: none

## Changes

- Replaced disclosure-time recursive directory enumeration with a complete bounded folder-tree snapshot loaded on the utility queue.
- Added a pure in-memory projection from the tree snapshot to visible rows based on persisted expanded/collapsed paths.
- Kept explicit refresh and folder lifecycle paths authoritative by rebuilding the tree snapshot from disk.
- Corrected the collapsed note-list title offset from `-58pt` to `-7pt` after same-state QA exposed an overlap with the compact sidebar button.
- Added regression coverage proving disclosure does not rescan disk and that collapsed title/button frames do not intersect.

## Verification

- Focused nested-folder, snapshot-disclosure, and library-layout tests passed.
- Full `swift test` and `git diff --check` passed.
- Packaged and strictly signature-verified `/Applications/Mudsnote.app`.
- Installed library smoke passed at `/tmp/mudsnote-installed-library-smoke-186-packaged`.
- Expanded visual QA: `/tmp/mudsnote-folder-snapshot-visual-186-expanded-final/apple-notes-vs-mudsnote.png`.
- Collapsed visual QA: `/tmp/mudsnote-folder-snapshot-visual-186-collapsed-final/mudsnote-library.png`; title and sidebar button no longer overlap.

## Decisions

- Treat folder disclosure as an in-memory view-state projection rather than a filesystem refresh trigger.
- Keep explicit refresh and folder mutations as the boundaries that replace the authoritative tree snapshot.
- Pair measured compact offsets with geometric non-overlap tests.

## Next

- Continue from same-state visual evidence, prioritizing remaining source hierarchy and complex editor-content differences.
