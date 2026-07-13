# 2026-07-13 iOS Recently Deleted selection

## Request

Continue the iPhone Apple Notes parity target by extending Notes-style multi-note
selection through the complete Recently Deleted lifecycle, including safe batch
restore and permanent deletion.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `f935546`
- Concurrent macOS source, test, script, roadmap, changelog, and handoff edits were
  preserved and excluded.

## Changes

- Recently Deleted now exposes a Notes-style options menu, Select Notes mode,
  Select All/Deselect All, live selection count, Done, and one bottom action bar.
- The bottom bar restores selected notes or permanently deletes them after an
  explicit destructive confirmation. Selection exits only after success.
- Batch restore prevalidates every trash record, resolves destination collisions,
  restores pin state once, removes recovery metadata only after payload moves, and
  rolls the entire transaction back when any step fails.
- Batch permanent deletion first moves every payload and metadata pair into a hidden
  transaction directory. A failed operation rolls staged files back; an interrupted
  process is recovered on the next trash inventory load instead of silently losing
  the selected notes.
- App-level batch operations refresh inventory and active search state once and
  report localized success or recovery errors.
- New controls and statuses are localized in English and Simplified Chinese.

## Verification

- Generic iOS Simulator build passed, including String Catalog compilation.
- Focused storage coverage verified selection-wide prevalidation, collision-safe
  batch restore, pin restoration, prevalidated permanent deletion, and recovery of
  an interrupted staging transaction.
- Focused UI automation completed the full destructive lifecycle: select two notes,
  move both to Recently Deleted, select and restore both, move them back again,
  Select All, confirm permanent deletion, and reach the empty state.
- Final full App and UI suite: 98 passed, 0 failed, 0 skipped (71 unit/integration
  and 27 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Final result bundle:
  `/tmp/MudsnoteTrashSelectionFinalFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_21-27-42-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteTrashSelectionDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- The Release app was installed successfully on MudsPhone (iPhone Air). Automatic
  launch was attempted, but SpringBoard rejected it because the device was locked;
  unlock-state visual smoke remains pending.

## Decisions

- Recently Deleted uses the same explicit selection grammar as ordinary note lists,
  but its action bar contains only Restore and destructive permanent deletion.
- Permanent deletion uses recoverable staging so a process interruption favors a
  reappearing deleted note over silent partial data loss.
- Filesystem batches remain store transactions; SwiftUI owns only selection state
  and never assembles repeated single-item mutations.

## Next

- Unlock MudsPhone and launch the already installed Release for a visual smoke of
  Recently Deleted selection and confirmation behavior.
- Continue the next Notes-parity retrieval, organization, or editor gap.
