# Mudsnote Notes

When working in this repo:

1. Read `README.md` first.
2. Read `docs/AI_HANDOFF.md` before substantial feature work, bugfixing, or UI changes.
3. Use `agent-memory/START_HERE.md` before opening deeper project memory or legacy `.codex` memory.
4. Treat `CHANGELOG.md` as user-visible iteration history, not as the only source of technical truth.
5. For quick-capture UI work, expect changes to span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
6. Declare every implementation task as `macos`, `ios`, or explicitly `both` before validation.
7. Validate macOS work with `./scripts/verify macos pr|full|live`; prefer a packaged-app smoke over screenshot-only validation.
8. Validate iOS work with `./scripts/verify ios pr|full|live`; never run `package_app.sh` or mutate `/Applications/Mudsnote.app` from an iOS-only task.
9. Use `./scripts/verify both ...` only when the user request explicitly spans both platforms. A dual-platform live run is allowed to install both artifacts in sequence.

## Delivery

- Follow `/Users/Donald/Code/Devflow/README.md` and use `/Users/Donald/Code/Devflow/bin/devtask`.
- Devflow may continue to call `./scripts/verify pr|full`; the dispatcher detects a single-platform diff and delegates only to that platform. Documentation-only changes run policy checks without building either app.
- `live` always requires an explicit platform argument or `MUDSNOTE_PLATFORM_SCOPE`; it never infers an installation target.
- Concurrent worktrees share `/Applications/Mudsnote.app` and the connected iPhone, so never run another platform's live flow as incidental verification.
- PR CI must not access iCloud, Keychain, real note folders, personal settings, credentials, or other user data.
