# Snapshot-first initial keyboard search

## Decision

- A keyboard search flush may use synchronous ranked search only when an active in-memory search session already exists.
- The first flush filters the loaded scope snapshot by title, preview, and tags, then schedules detached indexed search.
- Scope filtering for the provisional result mirrors All, Recent, Inbox, Folder, Tag, and Recently Deleted navigation.

## Verification

- The regression test verifies Return opens a title-matched provisional result while `activeSearchSession` remains nil, then waits for the detached task and verifies the session is published.
