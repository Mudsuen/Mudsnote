# Immediate list metadata after autosave

## Decision

- A successful library save updates both the source snapshot and the visible note-list projection before returning.
- Empty-query views reproject the current scope from memory, then rebuild sorting and date groups while preserving selected paths.
- Source counts refresh from the same snapshot.
- Active-query views schedule detached indexed search rather than synchronously rebuilding search state.

## Verification

- The existing autosave regression now asserts the visible result snippet changes immediately without invoking the previous manual cached-snapshot refresh helper.
