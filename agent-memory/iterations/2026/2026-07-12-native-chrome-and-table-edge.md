# 2026-07-12 Native chrome and table edge

## Request

- Fix the missing right border on rendered tables.
- Give toolbar buttons native macOS 26 material.
- Match the supplied Apple Notes expanded and collapsed sidebar-region references.

## Baseline

- Branch: `main`
- HEAD: `b774534`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- Toolbar groups used static dark CALayer fills; the source pane was a flat opaque split region; native text tables requested 100% content width and clipped the trailing stroke.

## Changes

- Set native `NSTextTable` content width to `99.25%`, preserving responsive layout while keeping the right stroke inside the text container.
- Replaced editor tools, file actions, list options, and New Note custom backgrounds with `NSGlassEffectView` using regular macOS 26 glass.
- Kept established compact geometry: `184x32`, `72x32`, and `30x30`.
- Removed obsolete custom fill/border constants and rendering functions.
- Changed the source root to a dark `.sidebar` material surface with a `24pt` rounded boundary and restrained separator outline.
- Preserved existing persisted split widths, tracking separators, and source hide/show behavior so collapse moves the note list to the left while retaining unified-toolbar controls.

## Verification

- AppKit tests assert native glass types, radii, compact geometry, sidebar material/boundary, collapsed/expanded behavior, and a `99.25%` percentage table width.
- Installed expanded screenshot shows the independent dark rounded source region, native glass controls, and complete table right border.
- Installed collapsed screenshot shows the note list occupying the left edge with library title/sidebar control retained in the unified toolbar and no overlap.
- Full Swift suite passed after migrating toolbar-action tests to the nested native glass buttons.
- Final package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.

## Decisions

- Use macOS 26 `NSGlassEffectView` directly rather than reproducing glass with CALayer opacity.
- Keep a fractional native table width instead of drawing a second custom border overlay.

## Next

- Continue titlebar/sidebar top-region fidelity and complex attachment preview parity.
