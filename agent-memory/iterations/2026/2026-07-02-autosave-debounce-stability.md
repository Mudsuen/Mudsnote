# 2026-07-02 Autosave debounce stability

## Context

While validating the wider Notes-like library window, full parallel app tests repeatedly exposed that `libraryWindowAutosavesEditedExistingNote` could miss the save even though the same test passed when isolated. The production autosave debounce used a RunLoop-backed `Timer`, which is fragile under UI test load.

## Change

- Replaced the library editor autosave `Timer` with a cancellable `Task<Void, Never>` debounce.
- Cancels pending autosave work on close, explicit save, or replacement autosave.
- Kept the debounce interval at 0.8 seconds.
- Updated the autosave regression to poll for the eventual saved state up to 3 seconds instead of assuming a precise wake-up instant.

## Verification

- `swift test --filter 'libraryWindowAutosavesEditedExistingNote|libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch'` passed.
- `swift test` passed with 77 tests.
- `./scripts/package_app.sh` passed.
- `./scripts/visual_notes_qa.sh` passed.
