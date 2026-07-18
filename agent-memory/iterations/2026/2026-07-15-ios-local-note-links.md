# 2026-07-15 iOS local note links

## Request

Continue the iPhone Apple Notes parity target while preserving Mudsnote's faster
new-note and quick-note workflow and portable Markdown storage.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `eb13ceb`
- Dirty files before work: none
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Gap

- The saved-note editor could create web links but could not link directly to
  another note, despite note-to-note navigation being a core current Notes flow.
- Plain Markdown note links were also mistaken for attachment rows, so they could
  not render or navigate correctly in the reading surface.
- Renaming or moving Markdown files could silently break relative links.

## Changes

- Added a searchable Link to Note picker inside the existing link editor. It
  searches note titles and paths, excludes the current note, and fills both the
  visible label and portable relative destination.
- Writes standard relative Markdown paths such as `./Projects/UI%20Lifecycle.md`
  and `../Reference/Topic.md`, with percent-encoded path segments for spaces and
  non-ASCII names.
- Validates every local destination against the library root, rejects external
  schemes and path traversal, and keeps missing links recoverable with a clear
  Linked note not found message.
- Rendered note links use the Notes-like yellow link hierarchy. Tapping one opens
  the destination inside the current half-sheet or full-screen reader, while a
  Previous Note control preserves in-sheet navigation history. External links
  still use the system URL handler.
- Corrected attachment parsing so only real `Attachments/` destinations become
  attachment cards; ordinary local-note and web links remain rendered Markdown.
- Added transactional link maintenance for note rename, single-note move,
  multi-note batch move, folder rename, and folder move. Both inbound and outgoing
  relative links are recalculated, caches are invalidated, and already-written
  files are restored if any later filesystem step fails.
- Added English and Simplified Chinese picker, search, history, and recovery copy.

## Verification

- Generic iOS Simulator build, String Catalog JSON validation, and `git diff --check`
  passed.
- Focused unit coverage passed for relative-path generation, percent encoding,
  traversal rejection, rendered-link attributes, attachment discrimination, and
  transactional links across note/folder rename and move operations.
- Focused UI coverage created a link through the searchable note picker, verified
  its raw Markdown, saved it, followed the rendered link, and returned through
  in-sheet history.
- Visual inspection confirmed a stable half-sheet and Notes-like rendered yellow
  link. Retained evidence:
  `/tmp/mudsnote-note-links-full-attachments/496A9C9D-1E91-4C6A-84E9-58A4EF6FD69E.png`.
- Final full App and UI suite: 120 passed, 0 failed, 0 skipped.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification, leaving no booted simulators.
- Final result bundle: `/tmp/MudsnoteNoteLinksFullFinal.xcresult`.
- Signed Release build passed from the final source at
  `/tmp/MudsnoteNoteLinksRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained USB-visible but `unavailable` to CoreDevice on iOS 27.0 beta.
  Installation failed with CoreDevice error 1011 because the device could not be
  located; no physical install or launch claim was made.

## Decisions

- Links remain ordinary portable Markdown rather than a proprietary graph database
  or private Notes-style store.
- Explicit `./` prefixes are preserved for same-level and descendant destinations
  so Foundation and SwiftUI do not reinterpret them as web URLs.
- Link repair is part of the same filesystem transaction as rename and move; path
  maintenance is not delegated to a later best-effort index job.
- Trashed notes are intentionally missing while in Recently Deleted. Restoring them
  to the original path restores the existing links without rewriting note content.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release and repeat create, follow, edit, move, rename, and back-navigation checks
  on the physical iPhone.
- Add an indexed backlinks surface so users can discover notes that reference the
  current note without sacrificing the portable Markdown source of truth.
