# Mudsnote Notes

When working in this repo:

1. Read `README.md` first.
2. Read `docs/AI_HANDOFF.md` before substantial feature work, bugfixing, or UI changes.
3. Use `agent-memory/START_HERE.md` before opening deeper project memory or legacy `.codex` memory.
4. Treat `CHANGELOG.md` as user-visible iteration history, not as the only source of technical truth.
5. For quick-capture UI work, expect changes to span `EditorWindowController.swift`, `Chrome/`, and `MarkdownRichEditor.swift`.
6. Validate meaningful changes with `swift test` and `./scripts/package_app.sh`, then prefer a packaged-app smoke over screenshot-only validation.

## Delivery

- Follow the short policy at `/Users/Donald/Code/Devflow/docs/workspace-delivery-policy.md`; use one fresh Codex task per Devflow implementation.
- During iPhone development, reuse one DerivedData through `./scripts/verify_ios`; run unit and targeted UI checks first, then one full UI regression at the final batch gate.
- Let `devtask pr` run the PR verification. Poll long tests every 45–60 seconds and return only summaries or failure evidence to the conversation.
- PR CI must not access iCloud, Keychain, real note folders, personal settings, credentials, or other user data.
