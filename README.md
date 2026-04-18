# Mudsnote

Mudsnote is a compact macOS quick-capture app for Markdown notes.

It is designed for fast idea capture:

- Global hotkey to show or hide a floating capture window
- Native macOS floating panels for quick capture and pinned notes
- Plain Markdown file storage
- Rich-text editing with Markdown round-trip serialization
- Inline tags, slash commands, autosave drafts, and recent note reopening

## Features

- Menu bar app
- Quick capture window
- Floating note window
- Global shortcuts
- Local Markdown files
- Draft autosave and restore
- Inline tag suggestions
- Slash commands
- Search and reopen recent notes

## Requirements

- macOS 13 or later
- Xcode 16 / Swift 6 toolchain

## Build

```bash
swift build
```

## Run Tests

```bash
swift test
```

## Package As an App

```bash
./scripts/package_app.sh
```

The packaged app bundle is written to `dist/Mudsnote.app`.

## Project Status

This project is under active development.

See [CHANGELOG.md](CHANGELOG.md) for iteration history and known issues.

## License

Mudsnote is released under the [MIT License](LICENSE).
