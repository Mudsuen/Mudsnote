# 2026-07-10 trash count IO

## Request

Continue Apple Notes UI parity while making the Mudsnote architecture as performant as practical.

## Baseline

- Branch: `main`
- HEAD before work: `7e3d8e2 Focus library on core Notes workflows`
- Dirty files before work: none
- Confirmed hotspot: every source-count refresh called `listTrashedNotes(limit: 10_000)`, which loaded and parsed every trashed Markdown file only to use the resulting array count.

## Changes

- Added `NoteStore.trashedNoteCount()` as a filesystem-only Markdown count.
- Replaced the library source-count path with the lightweight count API.
- Kept file enumeration live rather than adding a long-lived count cache, so external trash-directory changes remain visible.
- Added count assertions across trash, restore, re-trash, and permanent-delete lifecycle tests.

## Verification

- Passed focused core trash lifecycle, library trash lifecycle, and empty-folder source-count tests.
- Passed full `swift test`: 104 tests.
- Passed `git diff --check`.
- Passed `./scripts/package_app.sh`; installed `/Applications/Mudsnote.app`.
- Packaged-app accessibility smoke confirmed the normal library window, `Recently Deleted`, its count, note list, and toolbar remain present.

## Decisions

- Source counts must not hydrate note bodies.
- Prefer a live lightweight filesystem count over a stale in-memory count unless directory-change invalidation is added.

## Next

- Continue auditing main-thread source refresh and note-list reload work before adding new metadata features.
