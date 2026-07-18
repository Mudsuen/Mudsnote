# 2026-07-15 main-window Markdown open

## Request

Open Markdown files in the main library window instead of the quick-entry window, and make quick capture saving less visually abrupt.

## Baseline

- Branch: `main`
- HEAD: `b6c20cc`
- Dirty files before work: none

## Changes

- Route Launch Services and File > Open documents into the existing three-pane library.
- Project explicitly opened files into All Notes without configuring or scanning their parent folders.
- Preserve the current note before switching and save external documents at their original paths.
- Replace quick capture's wide Cancel/Save pills with compact native icon actions and reduce the footer shelf height.

## Verification

- Commands run: focused main-window and quick-capture regressions, `swift test`, `./scripts/package_app.sh`, installed-app Launch Services smoke, accessibility inspection, and code-signature verification.
- App/page/package actually opened: `/Applications/Mudsnote.app` opened `/private/tmp/mudsnote-main-window-open.md` in `Mudsnote 笔记`; quick capture was launched separately with `--quick-capture` and visually inspected.
- Result: All 166 tests passed. The final signed package routed the fixture into the standard `Mudsnote 笔记` window with its list row, title, and body selected; quick capture rendered the compact icon-only footer actions.
- Not verified: none for this scope.

## Decisions

- Explicit external files are temporary library projections, not imported copies and not new configured source folders.
- Quick capture keeps its dedicated destination shelf, but completion commands use familiar icons rather than dialog-style text pills.

## Next

- None for this scope.
