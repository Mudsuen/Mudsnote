# 2026-07-13 iOS Notes product baseline

## Request

Make the Mudsnote iOS app follow Apple Notes' overall core product model, excluding
features that do not fit, while treating Mudsnote's New Note and Quick Note behavior
as the main differentiation.

## Baseline

- Branch: `main`
- HEAD: `f91eab5`
- Dirty files before work:
  - `Sources/Mudsnote/LibraryWindowController.swift`
  - `Tests/MudsnoteAppTests/MarkdownRichEditorTests.swift`
  - `scripts/visual_notes_qa.sh`
- The dirty files are concurrent macOS work and are not part of this iteration.

## Changes

- Defined the iPhone Apple Notes parity target, included capabilities, exclusions,
  architecture boundary, phased delivery, and artifact-based acceptance rule.
- Recorded the durable product decision in project-local memory.
- Preserved Mudsnote's unified capture pipeline as the replacement for conventional
  New Note and Quick Note entry.

## Verification

- Documentation-only product/architecture checkpoint.
- Source and app verification will be recorded in the first implementation phase.
- No simulator was started.

## Decisions

- See `agent-memory/decisions/2026-07-13-ios-apple-notes-core-target.md`.

## Next

- Implement P0 folder/note lifecycle primitives before expanding visible chrome.
- Continue using one iPhone simulator with parallel testing disabled.
- Install the Release build on the connected iPhone when CoreDevice reports it as
  available.
