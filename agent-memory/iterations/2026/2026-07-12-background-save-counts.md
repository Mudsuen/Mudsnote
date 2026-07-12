# Background source-count aggregation after save

## Decision

- Autosave updates the visible note-list projection immediately.
- Folder, tag, and Inbox aggregate counts rebuild on a utility task from the immutable source snapshot.
- A monotonically increasing generation cancels stale count publications.
- Captured and current folder-path sets must match before applying the count index.
- Window close cancels the task.

## Verification

- The autosave regression verifies visible snippet replacement before awaiting count work, then awaits the task and verifies the All Notes count.
