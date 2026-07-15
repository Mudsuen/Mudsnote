# 2026-07-15 iOS tag lifecycle

## Request

Continue the iPhone Apple Notes parity target by adding Notes-style tag rename
and delete while preserving Mudsnote's portable Markdown source of truth, fast
new-note flow, and quick-note capture model.

## Baseline

- Branch: `main`
- HEAD: `1ae1330`
- Dirty files before work: none
- Scope remained iPhone-only; no iPad validation was run.

## Changes

- Added one shared Markdown tag syntax layer for normal notes, Inbox quick notes,
  metadata extraction, validation, and mutation. Matching remains case-,
  diacritic-, and width-insensitive.
- Tag recognition accepts Unicode letters, numbers, underscores, and internal
  hyphens while ignoring fenced code, inline code, and URL fragments.
- Added transactional library-wide rename and delete across active Markdown
  notes and `Inbox.md`. The store precomputes all updates, detects external
  edits before each coordinated write, rolls back completed writes on failure,
  and reports rollback failure explicitly.
- Hidden files, symlinks, and Recently Deleted content remain outside tag
  mutation. Search, metadata, library, selected-note, and selected-quick-note
  state refresh after a successful change.
- Added Notes-style long-press actions to the All Tags browser, with validation,
  pending-capture protection, destructive confirmation,
  target-specific confirmation titles, and Simplified Chinese localization.
- The All Tags flow uses native `Menu(primaryAction:)`: short press still cycles
  include/exclude filtering, while long press opens the tag action menu. This
  avoids SwiftUI's incorrect first-item context-menu binding inside a custom
  `Layout`, which could otherwise target a different tag after an in-place rename.
- Added focused store/syntax tests and an end-to-end UI regression that renames
  `#project` to `#project-client`, then immediately removes `#quick` from both
  the browser and Inbox content without affecting the renamed tag.

## Verification

- `git diff --check` passed.
- Focused tag syntax/store tests passed in
  `/tmp/MudsnoteTagLifecycleFocusedUnit.xcresult`.
- Focused rename/delete UI coverage passed in
  `/tmp/MudsnoteTagLifecycleFocusedUIFixed.xcresult`.
- Visual inspection confirmed that only `#project-client` and `#work` remain,
  and the quick note contains only `#project-client`. Evidence:
  `/tmp/mudsnote-tag-lifecycle-passed/51CC4E20-D387-485C-8414-2C29E34E5E05.png`.
- Final full suite passed 125 tests with 0 failures: 88 app/unit tests and 37 UI
  tests. Result bundle: `/tmp/MudsnoteTagLifecycleFullFinal.xcresult`.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing
  disabled. All simulators were shut down afterward.
- Signed Release build passed at
  `/tmp/MudsnoteTagLifecycleRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- CoreDevice listed MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`) as
  `unavailable`. Installation was attempted and failed with CoreDevice error
  1011 because Xcode could not locate an available device session; no physical
  install or launch claim was made.

## Decisions

- Markdown remains authoritative. Tag management rewrites exact visible tag
  tokens instead of introducing a proprietary tag database.
- Rename/delete is all-or-rollback across active notes so the UI never reports
  success for a partially changed library.
- Recently Deleted content is immutable from active tag management, matching
  its recovery role and avoiding surprising changes to recoverable notes.
- Native Menu primary actions are the stable interaction boundary for chips
  that need both a normal tap and a long-press menu inside the flow layout.

## Next

- Add local Smart Folders based on saved tag/date/attachment filters.
- Restore MudsPhone CoreDevice availability, install the signed Release, and
  repeat rename/delete across a normal note and quick note on hardware.
