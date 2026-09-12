# Mudsnote AI Handoff

Compact current state only. Historical evidence lives in `CHANGELOG.md`, project
memory, and Git history.

## Route

This file is exception context, not a default prerequisite. Start from a clean
Git checkpoint and a routed source search; read this only when current
constraints are relevant. Use `docs/ARCHITECTURE.md` only for boundary changes.

## Product State

Mudsnote is a local-first Markdown notes app. Plain `.md` files and portable
relative attachments are canonical across separate macOS and iPhone apps.

### macOS

- Native two-column library: material note list plus rich editor; folders and
  flat tags live in a transient native picker. Commands live in menus/shortcuts.
- Finder/Open Markdown routes into the library without registering an external
  file's parent. Registered roots are never moved or deleted on removal.
- Quick capture remains a separate compact title/body flow.
- Settings distinguishes the default new-note destination from registered roots;
  removing a root unregisters it without deleting files.
- Optional AI commands use the signed-in local Codex runtime through ephemeral
  read-only execution; no separate local-model service is required.
- The nonactivating selection-format panel preserves editor focus, applied state,
  rich-format shortcuts, undo/redo, and Markdown source switching.
- AppKit owns native outline/table/collection behavior; Mudsnote owns Markdown
  models, projections, commands, and asynchronous validation.
- Installed target: `/Applications/Mudsnote.app`.

### iPhone

- A plain note list opens folders in a native material sheet. iPhone reading
  uses one large sheet; regular-width iPad keeps list and editor side by side.
- Bidirectional links show outgoing references, backlinks, and local suggestions
  on demand. Legacy layer metadata stays readable without hierarchy controls.
- Folder access, lifecycle mutations, pending writes, attachments, search,
  intents, and widget converge on the same validated filesystem state.
- Product/parity work may consult `docs/ios-apple-notes-parity-roadmap.md`.

## Durable Contracts

- Follow `docs/ARCHITECTURE.md` ownership and dependency direction.
- A verified local checkpoint is the ordinary integration baseline; only
  independent-gate changes use PR/CI.
- Paint from bounded snapshots; validate files off-main and reject stale results.
- Reuse projections, caches, selection, and mutation paths—no parallel index or
  filesystem scan for another presentation.
- Preserve exact-path saves for externally opened macOS documents.
- Markdown/front matter/tag/attachment format changes are explicitly `both`.
- Preserve legacy QuickMarkdown migration until deliberately retired.
- PR CI never reads user files, iCloud, Keychain, settings, or credentials.

## Interaction Contracts

- Quick capture is not a miniature library editor.
- List and gallery share one note model and selection.
- macOS source visual mouse-down may precede save-backed navigation commit.
- Return in the macOS title moves to body while IME remains field-editor-owned.
- iOS row, menu, and opened-note actions stay behaviorally consistent.
- Visual comparison requires identical window, pane, scale, source, and fixture.

## Verification Limits

Use `docs/delivery-workflow.md` and the platform-scoped `scripts/verify` entrypoint.
Screenshots do not prove input or persistence. Borderless drag and Accessibility
automation can be host-limited. Concurrent worktrees must not share incidental
`live` installs.
