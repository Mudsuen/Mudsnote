# 2026-07-12 Paragraph format menu

## Request

Continue Apple Notes editor parity without changing the accepted compact toolbar geometry.

## Baseline

- Branch: `main`
- HEAD: `42b227c`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- The library `Aa` menu contained only H1, inline traits, bullet, and numbered list; choosing an active H1 toggled it back to Body.

## Changes

- Expanded the paragraph command model to H1, H2, H3, Body, checklist, bullet, and numbered list.
- Reorganized the menu into paragraph, inline, and list groups with established macOS shortcuts.
- Added active-state checkmarks based on the selected paragraph kind or insertion-point inline attributes.
- Split paragraph application into one shared renderer with explicit `togglesOffWhenMatching` behavior.
- Format-menu style selection is idempotent; dedicated heading/checklist/list toolbar and shortcut actions remain toggles.
- Avoids rewriting or marking a document dirty when the chosen paragraph style already matches every selected line.

## Verification

- AppKit regression validates all 11 menu items, separators, shortcut masks, Body state, H2 application, repeated H2 idempotence, Body reset, checklist conversion, and Markdown round-trip.
- Production package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- Isolated installed-app smoke sent `Option-Command-2`, saved the note, and verified the on-disk Markdown contains `## plain` under the note title with one window.
- Full Swift suite passed together with the native inline-folder editor iteration.

## Decisions

- Paragraph style menus set a style; dedicated toolbar commands toggle a style.
- The shared paragraph renderer receives this semantic difference explicitly rather than inferring it from callers.

## Next

- Continue format-menu accessibility and mixed-selection state auditing, then inspect link insertion's modal workflow.
