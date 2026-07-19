# Mudsnote AI Handoff

This is the compact current-state handoff. It intentionally excludes iteration
logs: use `CHANGELOG.md`, `agent-memory/iterations/`, and Git history only when a
task needs old evidence.

## Read And Route

1. Read `README.md`, `AGENTS.md`, and `agent-memory/START_HERE.md`.
2. For substantial implementation, read this file once.
3. Run `./scripts/agent_context.sh --list`, then select one topic.
4. Read `docs/ARCHITECTURE.md` for a boundary change; otherwise open only the
   routed source and test files.
5. Search historical records only for the concrete behavior or incident at hand.

## Product State

Mudsnote is a local-first Markdown notes app with separate macOS and iPhone apps.
Plain `.md` files and portable relative attachments remain canonical.

### macOS

- The primary experience is a native three-pane Apple Notes-style library with
  source outline, bounded note projection, list/gallery modes, and rich editor.
- Finder and File > Open Markdown route into the library. Explicit external files
  are projected without registering their parent directory as a library root.
- Existing top-level folders can be registered without moving or copying them.
  Removing a registered root preserves its contents.
- Quick capture remains a dedicated compact title/body flow with destination and
  save controls; it does not reuse the full library chrome.
- AppKit owns native outline/table/collection behavior. Mudsnote supplies local
  Markdown models, bounded projections, commands, and asynchronous validation.
- The installed target is `/Applications/Mudsnote.app`.

### iPhone

- The iPhone app follows the same core Notes information model while preserving
  Mudsnote's capture-first entry and local Markdown storage.
- Security-scoped folder access, lifecycle mutations, pending writes, attachments,
  search, capture, App Intents, and the widget must converge on the same validated
  filesystem state.
- Use `docs/ios-apple-notes-parity-roadmap.md` only for iOS product scope or parity
  work; it is not default startup context.

## Durable Architecture Contracts

- Follow `docs/ARCHITECTURE.md` for ownership and dependency direction.
- Paint navigation from bounded in-memory snapshots, then validate files off the
  main actor. Reject stale asynchronous results with cancellation/generation and
  selected-document checks.
- Reuse existing projections, caches, selection, and mutation paths. Do not add a
  parallel note index or filesystem scan for another presentation.
- Preserve exact-path saves for explicitly opened external macOS documents;
  managed notes retain normal library filename behavior.
- Keep Markdown, front matter, tags, and relative attachment semantics portable
  across platforms. A storage-format change is explicitly `both`.
- Preserve legacy `QuickMarkdown` migration until compatibility is deliberately
  retired.
- Do not read iCloud, Keychain, real note folders, personal settings, credentials,
  or other user data in PR CI.

## Current macOS UX Contracts

- The library uses native source-list, split-view, toolbar, table, and collection
  behavior with the accepted compact Notes-like geometry.
- Source clicks may preview native visual selection before the logical save-backed
  navigation commits; do not couple visual mouse-down timing to persistence.
- Return in the library title moves focus to the first body line while leaving IME
  composition under the field editor.
- List and gallery are presentations of the same bounded note model.
- Editor title/body, links, tables, attachments, search highlights, and Markdown
  round-trip behavior must remain compatible with installed-app workflows.
- For visual calibration, reproduce the exact window, pane, display scale, source,
  selected note, and fixture state before comparing coordinates.

## Current iOS UX Contracts

- New Note and Quick Note use the capture-oriented flow rather than divergent
  document-creation models.
- Folder, tag, trash, gallery, search, attachment, and reader actions must remain
  consistent across row actions, menus, and opened-note surfaces.
- UI tests and temporary fixtures may exercise real workflows; PR CI must not use
  the user's iCloud container or connected-device data.

## Efficient Change Strategy

1. Declare `macos`, `ios`, or explicit `both`.
2. Use `agent_context.sh` to select a module and optionally search a regex inside
   only that route.
3. For a large file, locate symbols first and read at most about 200 lines around
   the relevant implementation. Do not reread confirmed regions after editing.
4. Keep a short confirmed-facts summary and use the focused diff as the new source
   context.
5. Run one focused test cycle, one corrective rerun if needed, then one final
   platform verification candidate.
6. Update documentation after the implementation is stable, and only in the file
   that owns the durable fact.

## Verification

Use the dispatcher rather than ad hoc build commands:

```bash
./scripts/verify macos pr|full|live
./scripts/verify ios pr|full|live
./scripts/verify both pr|full|live
```

- `both` is only for a request that explicitly spans both platforms.
- Devflow may call one-argument `pr|full`; it detects a single-platform diff.
- Documentation-only changes run policy checks without building either app.
- `live` always requires an explicit platform and is never a PR CI step.
- macOS live owns `/Applications/Mudsnote.app`; iOS live owns the connected iPhone.
- For library create/edit/save/search/attachment work, include the isolated
  installed-app `scripts/library_smoke.sh` flow when relevant.
- Screenshots alone do not prove focus, input, save, or persistence behavior.

## Known Verification Limits

- Borderless-panel synthetic drag checks can be less reliable than a focused
  installed-app smoke.
- Accessibility scripting may fail under host permission or display-capture
  conditions; distinguish host limitations from app regressions.
- Concurrent worktrees share installed targets, so never run another platform's
  live flow as incidental verification.
