# 2026-07-13 iOS editor autosave and conflict recovery

## Request

Continue the iPhone Apple Notes parity target with complete half-sheet and expanded
Markdown editing, while preserving local Markdown storage.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `22193ac`
- Concurrent macOS source changes were preserved and excluded from this change.

## Changes

- Added 700 ms debounced autosave while editing both Markdown documents and Inbox
  memo blocks.
- Serialized successive edits so text entered during an in-flight save is persisted
  in the next pass instead of being lost.
- Added visible Edited, Saving, Saved, and Not Saved states without showing a toast
  for every autosave.
- Kept the explicit Done action for immediately finishing editing after the latest
  draft is durable.
- Added a recovery dialog for external-write conflicts with choices to keep the
  local draft or reopen the saved version.
- Preserved one draft across medium and large presentation detents and blocked sheet
  dismissal only while a draft is still unsaved.
- Invalidated list metadata after document saves so titles and previews refresh.
- Added bilingual editor state and recovery copy.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused autosave UI flow passed: edit, wait for Saved, close the sheet, reopen the
  document, and verify the new content remains.
- Final App and UI suite: 56 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled.
- All simulators were shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteEditorAutosaveFinal.xcresult`
  - `/tmp/MudsnoteEditorAutosaveFullFinal.xcresult`

## Decisions

- File writes remain actor-serialized and retain optimistic conflict detection.
- Autosave updates existing local Markdown in place; it does not introduce a
  database or proprietary document format.
- An unresolved save error keeps dismissal disabled, preserving the user's draft
  until they explicitly choose a recovery path.

## Next

- Add attachment insertion/removal from the full editor and continue toward direct
  rendered Markdown editing rather than exposing raw syntax during normal use.
