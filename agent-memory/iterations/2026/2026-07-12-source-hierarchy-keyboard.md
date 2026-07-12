# 2026-07-12 Source hierarchy keyboard navigation

## Request

Continue Apple Notes desktop parity and extend the newly added source-list keyboard model without duplicating folder state.

## Baseline

- Branch: `main`
- HEAD: `0c8e11d`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- Up/Down source navigation existed, but nested folder disclosure and parent-child movement remained pointer-only.

## Changes

- Added semantic enter/leave hierarchy commands to `LibrarySourceButton` for both raw Left/Right keys and AppKit `moveLeft:`/`moveRight:` responder paths.
- Right expands a collapsed folder and stays on it; a later Right activates its first visible direct child.
- Left collapses an expanded folder and stays on it; when already collapsed or leaf-only, Left activates the nearest visible parent.
- Refactored disclosure mutation out of the button selector so pointer and keyboard paths share persisted collapsed/expanded sets and reload behavior.
- Reacquires focus and activation by `LibraryScope` after every disclosure rebuild instead of retaining removed button instances.

## Verification

- Focused nested-folder regression covers expand, enter child, return parent, collapse, and return root.
- Production package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- Isolated installed-app smoke reproduced `Projects -> expand -> Client -> Projects -> collapse -> Notes` through real key events, confirmed child-row visibility at each stage, and kept one window.
- Full Swift suite is the final gate for this iteration.

## Decisions

- Folder hierarchy keyboard behavior reuses `sourceFolderRows`, `collapsedFolderPaths`, and `expandedFolderPaths`; there is no separate keyboard tree.
- Views are reacquired after disclosure rebuilds using URL-backed scopes.

## Next

- Continue P4 accessibility and context-state audits, then return to complex editor-content parity.
