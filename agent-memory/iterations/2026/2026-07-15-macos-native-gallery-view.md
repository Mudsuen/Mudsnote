# 2026-07-15 macOS native gallery view

## Request

Continue lightweight Apple Notes parity on macOS, prioritizing useful native behavior and performance rather than non-core features.

## Baseline

- Branch: `main`
- Resumed HEAD: `92245ce`; concurrent iOS audio work advanced HEAD to `c136968` without entering this macOS change.
- Dirty files before continuation: unfinished macOS gallery files from the active iteration plus separate iOS work. The iOS work was not edited or staged here.

## Changes

- Added persistent native list/gallery presentation modes and View-menu `Command-1` / `Command-2` commands.
- Gallery mode collapses the note list and uses the remaining workspace for reusable grouped preview cards while preserving the source sidebar.
- Reused the existing bounded list projection, table-backed selection model, thumbnail cache/tasks, search/source filtering, drag writers, and context menus.
- Kept hidden gallery state projection-only; collection items and thumbnail work begin only after the gallery is actually presented.
- Added same-workspace card opening, New Note fallback to list mode, empty states, and gallery-aware toolbar and split-layout persistence.
- Corrected real-app preview compression by constraining the preview and metadata stack to the full collection-item width.

## Verification

- Focused five-test gallery/settings/menu suite passed.
- The 10,000-row gallery projection stayed below the `100ms` debug regression gate.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- `./scripts/library_smoke.sh` passed against the installed app.
- Computer Use verified `Command-2`, `Command-1`, and double-click-to-editor against the installed app.
- Same-input official-reference comparison: `/tmp/mudsnote-gallery-vs-notes.jpg`.
- The pre-existing thumbnail deduplication regression initially exposed hidden gallery cell creation; after gating collection reloads to presented gallery state, that regression and the focused gallery suite passed together.
- Full `swift test` passed: 162 tests across two suites in 12.771 seconds.

## Decisions

- Keep the table projection as the canonical note-selection model and mirror collection selection into it, avoiding a duplicate document lifecycle.
- Use public AppKit collection/split primitives; Apple Notes private implementation is neither available nor required.
- Do not add a second scan, index, or thumbnail subsystem for gallery mode.

## Next

- Use a larger fixture to calibrate multi-column density against a current macOS 26 Apple Notes gallery capture.
- Consider richer Markdown page snapshots only if they can remain bounded and asynchronous.
