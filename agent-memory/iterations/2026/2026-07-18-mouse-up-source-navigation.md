# Mouse-up source navigation

## Contract

- Holding a primary click must not move the logical source or yellow accent to the pressed row.
- Releasing the click commits selection, accent, persistence, and navigation.
- Keyboard navigation remains immediate.

## Implementation

- `LibrarySourceOutlineView` snapshots selection on primary mouse-down and marks the pointer selection as deferred.
- Outline selection delegate updates during that interval repaint against `selectedScope` but do not activate the pending row.
- Mouse-up clears deferral and invokes the normal selection commit only if the row changed.

## Verification boundary

The source navigation test dirties the current note, begins pointer deferral, selects another outline row, and proves the logical scope, save callback, and yellow title remain unchanged. Finishing the pointer gesture must then select the new scope and expose yellow styling before the synchronous save callback returns.
