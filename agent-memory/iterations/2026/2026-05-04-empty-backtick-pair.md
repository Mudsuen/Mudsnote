# 2026-05-04 empty backtick pair

## Request

Fix the editor bug where typing a backtick caused the previously typed backtick to disappear.

## Baseline

- Branch: main
- HEAD: 17bcead
- Dirty files before work: `agent-memory/PROJECT_MEMORY_INDEX.md`; untracked `agent-memory/archive/`

## Changes

- Kept empty inline-code marker pairs visible while typing by treating ` `` ` as literal text until there is non-empty code content.
- Added a Markdown rich editor regression test for ` `` ` visibility and serialization.

## Verification

- Commands run:
  - `swift test` failed once because stale generated ModuleCache entries referenced both `/Users/Donald/code/Mudsnote` and `/Users/Donald/Code/Mudsnote`.
  - `rm -rf .build/arm64-apple-macosx/debug/ModuleCache && swift test` passed.
  - `./scripts/package_app.sh` failed once for the same generated release ModuleCache path conflict.
  - `rm -rf dist/build/arm64-apple-macosx/release/ModuleCache && ./scripts/package_app.sh` passed.
  - `open -n /Applications/Mudsnote.app --args --quick-capture` launched the packaged app.
- App/page/package actually opened: `/Applications/Mudsnote.app` quick-capture launch path.
- Result: packaged app launched; regression test covers the backtick disappearance path.
- Not verified: manual text entry in the packaged UI.

## Decisions

- Empty inline code markers stay literal while typing; non-empty inline code still renders as code.

## Next

- If this recurs in other paired Markdown markers, add typing-state guards for empty marker pairs before rendering them away.
