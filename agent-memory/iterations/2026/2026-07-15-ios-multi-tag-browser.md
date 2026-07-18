# 2026-07-15 iOS multi-tag browser

## Request

Continue the iPhone Apple Notes parity target while preserving Mudsnote's faster
new-note and quick-note workflow and portable Markdown storage.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `bb2c1e0`
- Dirty files before work: none
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Gap

- Tags from ordinary Markdown notes and Inbox captures already appeared together,
  but each home chip opened only one tag at a time.
- There was no Notes-style All Tags browser, combined tag filtering, any/all match
  mode, or exclusion state.
- Current Apple Notes supports selecting multiple tags, matching any or all, and
  tapping a selected tag again to exclude it. Mudsnote's single-tag navigation was
  therefore below the expected organization model.

## Changes

- Added an independent All Tags row to the folder home while retaining direct
  single-tag chips as shortcuts.
- Added a full tag browser that combines tags from saved Markdown files and Inbox
  quick notes without performing filesystem I/O from the view.
- A tag cycles through inactive, included, and excluded states. Included tags render
  as yellow checked chips; excluded tags use a minus and strikethrough treatment.
- Multiple included tags expose a compact Any/All segmented control. Exclusions are
  applied before the selected match mode.
- An empty filter shows every tagged note; untagged notes remain outside the tag
  browser. Clear Filters restores that state immediately.
- Tag comparison remains case-, diacritic-, and width-insensitive, matching the
  existing unified tag-summary identity.
- Filter state is ephemeral UI state derived from the immutable library snapshot.
  It does not create a proprietary database, alter Markdown, or add migration work.
- Added Simplified Chinese copy for the browser, match modes, filter reset, empty
  result, and include/exclude interaction hint.
- Kept the All Tags row and direct tag-chip card as separate navigation surfaces so
  SwiftUI does not merge their hit regions. The single-tag UI regression scrolls the
  chip fully above the fixed bottom command bar before tapping it.

## Verification

- Generic iOS Simulator build, String Catalog JSON validation, and `git diff --check`
  passed.
- Focused unit coverage passed for empty, any, all, case-insensitive, excluded,
  cycle, and clear semantics.
- Focused UI coverage passed for All Tags entry, include, exclude, any/all, saved
  Markdown and Inbox result combinations, clear filters, and the pre-existing
  single-tag shortcut.
- Visual inspection confirmed the Notes-style yellow selected chips, compact match
  control, clear action, and result hierarchy. Retained evidence:
  `/tmp/mudsnote-tag-browser-full-attachments/1C6C994C-6C87-4F94-99E8-0FF4B76A5AC9.png`.
- Final full App and UI suite: 122 passed, 0 failed, 0 skipped.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification, leaving no booted simulators.
- Final result bundle: `/tmp/MudsnoteTagBrowserFullFinal.xcresult`.
- Signed Release build passed from the final source at
  `/tmp/MudsnoteTagBrowserRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained USB-visible but `unavailable` to CoreDevice on iOS 27.0 beta.
  Installation failed with CoreDevice error 1011 because the device could not be
  located; no physical install or launch claim was made.

## Decisions

- Multi-tag selection is a projection over existing Markdown tags, not a new folder
  or saved-query format. This keeps portable source files authoritative.
- Any is the default combination because it broadens discovery; All is explicit for
  intersections. Excluded tags always remove a candidate regardless of match mode.
- Single-tag shortcuts remain available for the fastest common case, while All Tags
  owns the more advanced organization workflow.

## Next

- Add transactional tag rename and delete across saved notes and Inbox captures,
  then build local Smart Folders from saved tag/date/attachment filters.
- Restore MudsPhone CoreDevice availability, install the signed Release, and repeat
  include/exclude, any/all, quick-note opening, and saved-note opening on hardware.
