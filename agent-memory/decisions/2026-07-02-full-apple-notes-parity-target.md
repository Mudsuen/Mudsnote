# 2026-07-02 Full Apple Notes parity target

## Context

The user reviewed the current Mudsnote main window against Apple Notes and said completion is still far off. The new target is no longer "roughly Notes-like"; it is to fully replicate Apple Notes' core macOS function and UI.

## Decision

Mudsnote's macOS library becomes a full Apple Notes parity project, bounded by local-first Markdown storage and no Apple/iCloud private-service dependency.

The authoritative checklist is `docs/apple-notes-parity-roadmap.md`.

## Consequences

- Future desktop work should be selected from the roadmap, not from isolated visual tweaks.
- "Done" requires packaged-app behavior plus visual comparison against the Apple Notes screenshot.
- UI changes should first improve the Notes shell: toolbar, source list, note list, and editor metadata.
- Functional parity then fills in folders, trash, formatting, tables, attachments, and search.
- The iOS companion remains capture-first unless the user separately sets mobile Notes parity as a target.

## Rejected Direction

- Do not continue one-off styling changes without linking them to a parity checklist item.
- Do not implement iCloud sync or Apple Notes database access as part of this goal.
