# Installed library smoke

## Request

Continue the Apple Notes parity goal with stronger evidence for real installed-app workflows.

## Baseline

- Branch: `main`
- HEAD: `709537a`
- Dirty files before work: none

## Changes

- Added `scripts/library_smoke.sh` for the installed three-pane library.
- The script uses an isolated notes directory, defaults suite, and app-support directory.
- It creates a note via `Command-N`, writes title/body through AX values, verifies exact Markdown autosave, then searches and confirms the unrelated fixture is filtered out.

## Verification

- `bash -n scripts/library_smoke.sh` passed.
- Final installed smoke passed at `/tmp/mudsnote-installed-library-smoke-181-final`.
- `swift test`, packaging, and strict code-sign verification passed.
- Visual QA: `/tmp/mudsnote-library-smoke-visual-181/apple-notes-vs-mudsnote.png`; no visible regression.

## Decisions

- Do not use synthetic keystrokes for text content because the active Chinese input method can transform it.
- Use AX values for deterministic smoke text while retaining native keyboard commands for `Command-N` and `Command-F`.
- Keep the user library untouched by always supplying isolated store arguments.

## Next

- Extend the installed smoke to delete/restore, folder move, and attachment rendering.
