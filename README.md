# Mudsnote

Mudsnote is an open-source macOS menu bar app for fast Markdown note capture.
It is built for local-first writing workflows where notes stay as plain `.md`
files instead of being locked into an app-specific database.

## Features

- Menu bar access for quick capture
- Global hotkey for opening a floating note window
- Rich Markdown editing for headings, inline formatting, lists, and checklists
- Plain `.md` file storage in a user-selected notes folder
- Recent-note reopening and editing
- Configurable save shortcut, floating note shortcut, opacity, and note folders
- Standard macOS settings window
- Optional local AI commands for Markdown summarizing, grammar fixes, and task extraction

## Project Status

Mudsnote is actively maintained as a non-commercial open-source project. The
current focus is a compact, reliable macOS note capture experience with simple
Markdown interoperability.

## AI Features

AI is disabled by default and is designed as an explicit Markdown command layer,
not a chat workspace. When enabled, Mudsnote can use a local Ollama provider for:

- right-click AI actions in the editor
- `/summarize`, `/fix`, and `/todos` slash commands
- preview-before-apply insertion, replacement, or copy behavior

Mudsnote sends only the selected text, current paragraph, or active note needed
for the command you invoke. See `PRIVACY.md` for the data-flow boundary.

## Build

Run the platform-specific verification flow:

```bash
./scripts/verify macos pr
./scripts/verify ios pr
# Only for an explicitly dual-platform change:
./scripts/verify both pr
```

Live verification is also platform-scoped:

```bash
./scripts/verify macos live  # installs /Applications/Mudsnote.app
./scripts/verify ios live    # installs to the connected iPhone
./scripts/verify both live   # explicit dual-platform install
```

The one-argument `./scripts/verify pr|full` form remains available for Devflow and safely detects the changed platform. The one-argument `live` form is rejected because installation targets must be explicit.

Run the isolated installed-app library smoke:

```bash
./scripts/library_smoke.sh
```

This launches `/Applications/Mudsnote.app` against a temporary library and verifies native `Command-N`, title/body editing, autosave, toolbar search, move to Recently Deleted, restore, move to a folder, Finder-file attachment paste, portable Markdown storage, and attachment rendering after relaunch without touching the user's notes.

## Development Notes

- See `docs/AI_HANDOFF.md` for project architecture, current product state, verification expectations, and takeover guidance for another AI.
- See `CHANGELOG.md` for iteration history, known issues, and lessons learned.

## License

Mudsnote is released under the MIT License. See `LICENSE`.
