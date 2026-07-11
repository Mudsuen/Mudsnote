# 2026-07-11 library window frame persistence

## Goal

Make the compact Notes-like library behave like a desktop document workspace by restoring its last position and size without weakening deterministic visual QA.

## Baseline

- Source/list divider widths and source visibility already persisted.
- The main library window still recentered and returned to the default size on every process launch.
- Quick capture and floating note already used `StoredWindowFrame`; the library had no equivalent keys.

## Implementation

- Added `NoteStore.libraryWindowFrame` using four finite `UserDefaults` values through the existing frame reader/writer.
- The library restores a stored frame on ordinary presentation and otherwise uses the compact centered default.
- Extended `clampedPanelFrame` with an optional minimum size so stale, undersized, or offscreen library frames return to the nearest visible display safely without changing existing floating-panel behavior.
- Coalesced move and resize notifications into one write after 180ms; live-resize completion and window close flush immediately.
- Canonical visual-QA windows ignore and never overwrite the personal library frame.

## Verification

- Added core persistence coverage for the library frame.
- Added AppKit coverage for minimum-size/offscreen clamping, notification-driven frame persistence, close/reopen restoration, and canonical-QA isolation.
- Full Swift suite: 130 tests passed.
- Production package installed at `/Applications/Mudsnote.app` and passed strict deep code-signature verification.
- Installed smoke:
  - moved the single library window to System Events position `{120,90}`
  - resized it to `1120x760`
  - confirmed stored Cocoa frame `x=120, y=230, width=1120, height=760`
  - terminated and reopened the process
  - confirmed the restored System Events position and size remained exactly `{120,90}` and `1120x760`
- Removed smoke-only frame preferences and reopened the formal library at `1080x720` with `250/250` splitters.

## Decision

- Keep workspace geometry in tiny preferences, separate from note metadata and the search index.
- Treat deterministic QA geometry as an explicit launch mode, not as user state.
