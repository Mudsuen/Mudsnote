# 2026-07-19 macOS settings, Codex, and selection shortcuts

## Scope

- Platform: macOS only.
- Keep iOS source and installation artifacts untouched.

## Changes

- Settings presents the default folder as the destination for newly created notes, with a direct Change action. Registered roots are called “Library Folders”; Mudsnote indexes them in place and unregistering one does not move, copy, or delete its files.
- Changing the default folder automatically registers the new root while retaining the old default as a library root, preventing existing notes from disappearing from the library.
- The opt-in AI command layer resolves the signed-in Codex CLI using the same candidate strategy as Tmate: configured path, process PATH, Homebrew locations, Codex.app/ChatGPT.app bundles, and NVM installations.
- Each AI request runs `codex exec` as an ephemeral, read-only, non-interactive job in the notes directory and reads only the final response. Settings exposes runtime status and optional executable selection, not provider URL, model server, or model plumbing.
- Selection-format buttons use hover and applied-state backgrounds. Applying a root or submenu command refreshes the button states without closing the nonactivating panel.
- Normal typing and deletion still dismiss the panel before editor handling. Formatting, Undo, and Redo key equivalents are handled by `MarkdownTextView`, so library and quick-entry surfaces share the same route.

## Verification contract

- Core tests cover Codex runtime resolution, persistence, and read-only ephemeral arguments.
- App tests cover Settings construction, selection-panel persistence/application state, formatting key equivalents, and formatting undo/redo.
- Validate through `./scripts/verify macos pr` and then `./scripts/verify macos live`; the live flow owns `/Applications/Mudsnote.app`.
