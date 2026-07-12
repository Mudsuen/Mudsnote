# Snapshot-first Recently Deleted search flush

## Decision

- Debounced Recently Deleted search continues to use detached full-text parsing.
- Keyboard-triggered debounce flushes first filter the existing trash snapshot by title, preview, and tags.
- The same flush immediately schedules detached full-text replacement so body-only matches remain available.

## Regression boundary

- The test removes the trashed file after controller snapshot hydration, then verifies a keyboard flush still returns the cached title immediately. A synchronous filesystem implementation would lose that result.
