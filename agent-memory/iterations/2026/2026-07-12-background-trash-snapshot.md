# Background Recently Deleted snapshot

## Decision

- Recently Deleted never scans or parses trashed Markdown as part of source navigation.
- The normal background snapshot validation task also loads the bounded trash snapshot.
- Trash counts come from that snapshot rather than a separate main-thread directory walk.
- Explicit trash, restore, and permanent-delete commands update the snapshot before reloading the visible scope.

## Verification

- A deferred-hydration regression test creates a trashed note after controller initialization, verifies the first Recently Deleted paint is the empty cached state, then waits for background validation to publish the note.
