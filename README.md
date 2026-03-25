# QuickMarkdown

Minimal macOS prototype for fast Markdown capture:

- Menu bar app
- Global hotkey to open a capture window
- Save notes as plain `.md` files
- Reopen recent notes for editing
- Configure the notes folder and shortcut

Build:

```bash
cd tools/QuickMarkdown
swift build
```

Package as an app bundle:

```bash
cd tools/QuickMarkdown
./scripts/package_app.sh
```

The packaged app is written to `tools/QuickMarkdown/dist/QuickMarkdown.app`.

Change log:

- See `tools/QuickMarkdown/CHANGELOG.md` for iteration history, known issues, and lessons learned.
