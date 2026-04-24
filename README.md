# Mudsnote

Minimal macOS prototype for fast Markdown capture:

- Menu bar app
- Global hotkey to open a capture window
- Save notes as plain `.md` files
- Reopen recent notes for editing
- Configure the notes folder and shortcut

Build:

```bash
swift build
```

Package as an app bundle:

```bash
./scripts/package_app.sh
```

The packaged app is installed to `/Applications/Mudsnote.app`.

AI handoff:

- See `docs/AI_HANDOFF.md` for project architecture, current product state, verification expectations, and takeover guidance for another AI.

Change log:

- See `CHANGELOG.md` for iteration history, known issues, and lessons learned.
