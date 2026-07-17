# Mudsnote iOS Apple Notes Parity Roadmap

## Product target

Mudsnote for iPhone should feel like Apple Notes for everyday note organization,
reading, editing, and retrieval while remaining a local-first Markdown app.
Mudsnote intentionally replaces Apple Notes' ordinary new-note entry with its own
fast capture workflow.

The product is not an Apple Notes client and must not read or write Apple's private
Notes database.

## Durable interaction contract

- The library follows the familiar folders -> note list -> note editor hierarchy.
- A saved item behaves like a normal note: it can be opened, edited, pinned, moved,
  searched, deleted, restored, and inspected without switching between raw and
  preview modes.
- The main New Note button opens Mudsnote capture instead of an empty Apple Notes
  editor. Submission dismisses the capture surface and returns to the library.
- New Note is the sole in-app creation control; there is no separate lightning Quick
  Note button, and its compact capture actions remain on one row.
- Widget, App Intent, deep-link, and in-app capture entry points use the same draft,
  target, attachment, queue, and commit pipeline.
- Markdown rendering is the default reading surface. Tapping the content enters a
  complete editor whose native sheet moves between half and full height by dragging
  the grabber; no duplicate full-screen button is shown.
- The iPhone is the only supported layout target. Simulator verification uses one
  iPhone destination with parallel testing disabled.

## Included core Notes capabilities

- Notes-like folder home, nested folders, counts, and note lists.
- Create, rename, reorder/sort, pin, move, trash, restore, and permanently delete.
- Direct Markdown editing with headings, emphasis, lists, checklists, quotes, code,
  links, undo, and redo.
- Full-text search across title, path, tags, body, referenced images, and scanned PDFs
  with useful result context and structured suggestions; Find in Note can include
  those attachments.
- Images, files, audio notes with local recording transcription, attachment browsing,
  and portable relative Markdown references.
- Print-ready, paginated PDF export through the native share sheet without rewriting
  the Markdown source.
- Offline-first writes, pending replay, external-edit conflict protection, and clear
  recovery states.
- Tags, recent notes, daily notes, Inbox capture stream, widgets, shortcuts, and
  quick capture as Mudsnote extensions to the Notes model.

## Explicit exclusions

- Phone-call recording.
- Apple Notes collaboration, shared folders, and share-link permissions.
- Apple account/database integration or proprietary Notes import that depends on
  private storage formats.
- iPad-specific layout and test work.
- Further iPhone table-authoring expansion is deferred for now; preserve the existing
  portable Markdown table support without prioritizing additional table UI.
- Features that require a server account when the same value can be delivered with
  local Markdown and iCloud Drive.

System export through the iOS share sheet can remain a file operation; it is not a
collaboration or share-link feature.

## Architecture boundary

The iOS app should converge on five layers:

1. `LibraryStore`: coordinated Markdown and attachment persistence, atomic mutation,
   trash, move, rename, folder operations, and conflict detection.
2. `LibrarySnapshot`: immutable folders, notes, memos, tags, attachments, counts, and
   search metadata published as one revision.
3. `SearchIndex`: bounded incremental full-text index derived from the snapshot and
   invalidated by revision.
4. `CapturePipeline`: immutable draft snapshot -> durable pending queue -> idempotent
   store mutation -> snapshot refresh.
5. SwiftUI features: folder home, note list, rendered reader/editor, capture sheet,
   search, attachments, and settings. Views do not perform filesystem I/O.

Library switching remains transactional: stale configuration tasks must never publish
state from a previously selected folder.

## Delivery phases

### P0 - Data model and lifecycle

- First-class folder tree, note identity, pin state, and trash representation.
- Atomic create, rename, move, delete, restore, and permanent-delete operations.
- Tests for path safety, external edits, queue replay, library switching, and every
  note lifecycle transition.

Exit: the entire lifecycle works against temporary Markdown libraries without UI.

### P1 - Notes navigation shell

- Notes-like folder home with system folders, user folders, tags, and counts.
- Consistent note-list rows with title, preview, date, folder, pin, and attachment
  metadata.
- Stable back navigation and preserved selection where appropriate.

Exit: users can navigate a real library without falling back to Files.

### P2 - Complete editor

- Rendered Markdown by default; tap to edit.
- Half-sheet reading/editing plus full-screen expansion.
- Autosave or explicit-save behavior with unsaved-change protection, external-edit
  conflict handling, attachments, formatting tools, and keyboard-safe animation.

Exit: ordinary Notes editing sessions can be completed entirely on iPhone.

### P3 - Retrieval and organization

- Full-text search, pinned notes, tags, sorting, folder move, trash, and restore.
- Search focus enters only from an intentional action and releases on navigation,
  outside interaction, or disappearance.

Exit: a large library remains quickly searchable and safely reorganizable.

### P4 - Mudsnote capture advantage

- One-row, keyboard-synchronized capture chrome.
- Fast target selection, image/file/audio-note attachments, continuous capture, and
  reliable dismissal after submission.
- Widget, Shortcut/App Intent, and deep-link parity with in-app capture.

Exit: capture is measurably faster than creating and filing a conventional note.

### P5 - Commercial release closure

- Failure and empty states, localization, privacy manifest, signing, archive, crash
  symbols, migration, performance, and destructive-action confirmations.
- One iPhone simulator for automated checks, followed by Release installation and
  launch smoke on the connected physical iPhone.

Exit: current Release artifact passes archive validation and the core lifecycle on a
physical iPhone.

## Acceptance rule

A phase is not complete from source inspection alone. It requires focused tests,
the single-iPhone suite when UI behavior changes, a Release build/archive, and a
real app flow. Physical-device verification remains required for release closure.
