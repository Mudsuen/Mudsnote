# 2026-07-13 iOS conflict resolution

## Request

Continue the iPhone Apple Notes parity target by replacing warning-only iCloud
conflict detection with a user-operable recovery flow. Preserve every Markdown
version and avoid destructive automatic merging.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `e0b5ba7`
- Pre-existing and concurrent macOS/documentation edits were preserved and excluded.

## Changes

- Conflict detection now considers only regular Markdown documents with recognized
  conflict-copy suffixes, avoiding false positives from ordinary filenames and
  non-Markdown resources.
- Settings now presents a dedicated conflict review screen instead of inert path
  warnings. Each conflict can be opened, kept as a normal note, or moved to
  Recently Deleted.
- Keeping a conflict uses a coordinated move, strips the provider conflict suffix,
  chooses a collision-safe filename, preserves exact Markdown content, and migrates
  pin state without overwriting the original note.
- Damaged pending-queue recovery warnings remain independently visible in Settings.
- The new flow and statuses are localized in English and Simplified Chinese.

## Verification

- Generic iOS Simulator build passed.
- Focused storage coverage verified false-positive filtering, exact content
  preservation, collision-safe recovery, original-file preservation, old-path
  removal, warning removal, and pin migration.
- Focused UI automation verified Settings -> Review Conflicts -> Keep as Separate
  Note -> recovered note visible in All Notes.
- Final full App and UI suite: 91 passed, 0 failed, 0 skipped (67 unit/integration
  and 24 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteConflictResolutionFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_19-48-56-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteConflictResolutionDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- The Release app was installed successfully on MudsPhone (iPhone Air). Automatic
  launch was then attempted, but SpringBoard rejected it because the device was
  locked; unlock-state launch and visual smoke remain pending.

## Decisions

- Conflict copies are never merged automatically because line-based Markdown merge
  could silently lose the user's preferred version.
- Keeping a conflict is a rename transaction, not a copy-and-delete sequence, so
  the file identity and exact bytes remain intact while provider suffixes are removed.

## Next

- Launch the installed build once MudsPhone is unlocked and visually smoke the new
  conflict screen against a real provider-generated conflict copy.
- Continue the next Notes-parity organization, retrieval, or editor gap.
