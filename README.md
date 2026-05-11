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

## Project Status

Mudsnote is actively maintained as a non-commercial open-source project. The
current focus is a compact, reliable macOS note capture experience with simple
Markdown interoperability.

## Build

Build the command-line target:

```bash
swift build
```

Package and install the macOS app bundle:

```bash
./scripts/package_app.sh
```

The packaged app is installed to `/Applications/Mudsnote.app`.

## Development Notes

- See `docs/AI_HANDOFF.md` for project architecture, current product state, verification expectations, and takeover guidance for another AI.
- See `CHANGELOG.md` for iteration history, known issues, and lessons learned.

## License

Mudsnote is released under the MIT License. See `LICENSE`.
