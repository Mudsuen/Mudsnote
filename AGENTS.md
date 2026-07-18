# Mudsnote Notes

When working in this repo:

1. Read `README.md` first.
2. Read `docs/AI_HANDOFF.md` before substantial feature work, bugfixing, or UI changes.
3. Use `agent-memory/START_HERE.md` before opening deeper project memory or legacy `.codex` memory.
4. Treat `CHANGELOG.md` as user-visible iteration history, not as the only source of technical truth.
5. For quick-capture UI work, expect changes to span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
6. Validate meaningful macOS changes with `swift test` and `./scripts/package_app.sh`, then prefer a packaged-app smoke over screenshot-only validation.
7. For iOS-only work, never run `./scripts/package_app.sh` and never mutate `/Applications/Mudsnote.app`; use the iOS Xcode/UI-test/device-install flow instead. Shared `swift test` or `./scripts/verify pr|full` checks are allowed because they do not install the macOS app.

## Delivery

- Follow `/Users/Donald/Code/Devflow/README.md` and use `/Users/Donald/Code/Devflow/bin/devtask`.
- Verify with `./scripts/verify pr|full|live` as appropriate.
- `live` is macOS-only. Concurrent worktrees share `/Applications/Mudsnote.app`, so an iOS task that runs `live` or `package_app.sh` will overwrite another task's installed macOS artifact.
- PR CI must not access iCloud, Keychain, real note folders, personal settings, credentials, or other user data.
