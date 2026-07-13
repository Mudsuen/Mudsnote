# 2026-07-13 iOS multi-note selection

## Request

Continue the iPhone Apple Notes parity target by adding Notes-style multi-note
selection and safe batch organization actions. Keep the Markdown-first storage
model and quick-capture behavior unchanged.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `75b5cc6`
- Concurrent macOS source and test edits were preserved and excluded.

## Changes

- All Notes and individual folder views now enter a dedicated selection mode from
  the existing options menu, with Select All, Deselect All, selection count, and
  Done controls matching the Notes interaction model.
- Selected rows use explicit circle/checkmark state and a single bottom action bar
  for Move, Pin or Unpin, and Delete instead of exposing per-row editing controls.
- Batch move, pin, and Recently Deleted operations are implemented as store-level
  transactions. Inputs are validated before mutation, filename collisions remain
  safe, pin state is migrated once, and partial move/trash failures are rolled back.
- App-level batch operations refresh inventory and search state once per completed
  transaction, close a selected open document when required, and keep selection
  active when an operation fails.
- The new controls, confirmations, status messages, and rollback error are localized
  in English and Simplified Chinese.

## Verification

- Generic iOS Simulator build passed.
- Focused storage coverage verified collision-safe batch moves, pin preservation,
  atomic rejection of a selection containing a protected Daily note, unpinning,
  and batch transfer to Recently Deleted.
- Focused UI automation verified selecting two Markdown notes and pinning both from
  the Notes-style bottom action bar.
- Final full App and UI suite: 95 passed, 0 failed, 0 skipped (69 unit/integration
  and 26 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteBatchSelectionFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_21-01-22-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteBatchSelectionDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- MudsPhone was still registered as the expected iPhone Air, but CoreDevice reported
  it as `unavailable` on two installation attempts, so this build could not be
  installed or launched in the current device session.

## Decisions

- Batch filesystem operations belong in the store rather than being assembled from
  repeated app-model calls, because transaction-wide validation and rollback are
  required to avoid partially moved or deleted selections.
- Folder selection hides child folders and excludes the current folder subtree from
  move destinations so selection remains unambiguously note-only and cannot create
  recursive folder moves.
- Selection exits only after a successful action; recoverable failures leave the
  user's chosen set intact.

## Next

- Reconnect or unlock MudsPhone until CoreDevice reports it as available, then install
  and launch the already signed Release artifact for a physical smoke test.
- Continue the next Notes-parity organization, retrieval, or editor gap.
