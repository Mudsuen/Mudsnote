# 2026-06-11 governance validation

## Request

Broader workspace governance: review/test projects, keep agent routing lean, and prioritize newer or less-discussed projects for usability and feature iteration.

## Baseline

- Branch: main
- HEAD: bde053d
- Dirty files before work:
  - `?? agent-memory/iterations/2026/2026-06-08-ios-companion-v03.md`
  - `?? iOS/`

## Changes

- No source changes.
- Re-ran the native validation path for the current macOS app.

## Verification

- Commands run:
  - `swift test`
  - `./scripts/package_app.sh`
  - `open -n /Applications/Mudsnote.app`
  - `pgrep -fl '^/Applications/Mudsnote.app/Contents/MacOS/Mudsnote$|Mudsnote.app/Contents/MacOS/Mudsnote'`
- App/page/package actually opened:
  - `/Applications/Mudsnote.app`
- Result:
  - `swift test` passed: 53 tests in 2 suites.
  - Packaging succeeded and installed `/Applications/Mudsnote.app`.
  - Installed app launched. A duplicate verification process was closed, leaving the pre-existing Mudsnote process running.
- Not verified:
  - No screenshot or interactive note-capture smoke was performed.
  - The untracked `iOS/` companion work was not inspected or modified.

## Decisions

- Treat the current macOS source tree as healthy for this governance pass.
- Keep the existing untracked iOS companion work out of this validation checkpoint.

## Next

- Review the iOS companion work separately before staging or integrating it.
- Add a non-interactive launch smoke mode if repeated app-open validation continues to create duplicate resident instances.
