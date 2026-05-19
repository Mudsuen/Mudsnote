# 2026-05-13 local AI command layer

## Request

Use the existing Chat app GPT Pro workflow to design and optimize Mudsnote, then add AI capabilities with right-click menu and slash-command entry points.

## Baseline

- Branch: main
- HEAD: e560ff9
- Dirty files before work: none in Mudsnote

## Changes

- Ran the Chat app `script/chat-workflow` with ChatGPT Pro and used the generated product/architecture recommendation.
- Added an opt-in local Ollama provider and AI prompt builder in `MudsnoteCore`.
- Added Settings controls for enabling AI, configuring Ollama Base URL/model, and testing connection.
- Added editor context-menu AI actions and slash commands for summarize, fix, and todos.
- Added `PRIVACY.md`, `SECURITY.md`, and CI.

## Verification

- Commands run:
  - `swift build`
  - `swift test`
  - `./scripts/package_app.sh`
  - `open -n /Applications/Mudsnote.app --args --preferences`
  - `open -n /Applications/Mudsnote.app --args --quick-capture`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app` Settings window opened.
  - `/Applications/Mudsnote.app` quick-capture panel opened.
- Result:
  - Initial build passed after wiring the AI MVP.
  - `swift test` passed with 52 tests.
  - Packaging succeeded to `/Applications/Mudsnote.app`.
- Not verified:
  - Live Ollama generation, because this depends on the user's local Ollama server/model state.

## Decisions

- AI is an explicit Markdown command layer, not a chat sidebar.
- First provider is local Ollama only; remote providers and Keychain storage are deferred.
- AI defaults to off and sends only the selected text, current paragraph, or active note for the invoked command.

## Next

- Run `swift test`, package, and smoke the Settings/editor surfaces.
