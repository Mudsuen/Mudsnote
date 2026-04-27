# Mudsnote Notes

When working in this repo:

1. Read `README.md` first.
2. Read `docs/AI_HANDOFF.md` before substantial feature work, bugfixing, or UI changes.
3. Use `agent-memory/START_HERE.md` before opening deeper project memory or legacy `.codex` memory.
4. Treat `CHANGELOG.md` as user-visible iteration history, not as the only source of technical truth.
5. For quick-capture UI work, expect changes to span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
6. Validate meaningful changes with `swift test` and `./scripts/package_app.sh`, then prefer a packaged-app smoke over screenshot-only validation.
