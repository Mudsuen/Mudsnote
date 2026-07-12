# 2026-07-12 Source keyboard navigation

## Request

Continue Apple Notes desktop parity while preserving the accepted compact visual scale and efficient local architecture.

## Baseline

- Branch: `main`
- HEAD: `fab4d08`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- Content-state visual QA showed stable editor geometry, but source rows remained mouse-only after activation.

## Changes

- Added `LibrarySourceButton`, a focusable `NSButton` subclass with no extra focus ring.
- Routed raw Up/Down key events and AppKit `moveUp:`/`moveDown:` responder commands into one source-navigation closure.
- Traversal uses the existing ordered `sourceButtons` array, so it naturally includes only currently visible folders, trash, and tags and adds no parallel navigation model.
- Source actions reclaim first responder after saving and reloading the selected scope, making pointer, accessibility, and keyboard activation converge.
- Boundary arrows are consumed while preserving the current source instead of moving focus into unrelated toolbar controls.

## Verification

- Focused AppKit regression covers action-acquired focus, raw key events, responder commands, selection synchronization, and the top boundary.
- Production package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- Isolated installed-app smoke activated `All iCloud` through Accessibility, confirmed source-button focus, navigated Down to `Notes`, then Up to `All iCloud`, with one window throughout.
- Full Swift suite is the final gate for this iteration.

## Decisions

- Source keyboard order comes from the rendered visible button order, not a duplicate tree model.
- Focus is finalized by the source action after scope reload, not by `mouseDown` timing.

## Next

- Extend source keyboard parity to hierarchy-specific Left/Right disclosure behavior without changing row geometry.
