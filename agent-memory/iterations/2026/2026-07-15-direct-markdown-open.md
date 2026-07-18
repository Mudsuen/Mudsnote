# 2026-07-15 direct Markdown open

## Request

Fix Mudsnote so Finder and the native Open command can open `.md` files directly.

## Baseline

- Branch: `main`
- HEAD: `210da70`
- Dirty files before work: none

## Changes

- Register Markdown as an editable document type in the packaged app.
- Handle AppKit open-file events during cold launch and while already running.
- Add a native File > Open command for one or more Markdown documents.
- Preserve external filenames and extensions during saves, including Command-S.

## Verification

- Commands run: `swift test`, focused external-editor regression, `./scripts/package_app.sh`, `plutil`, `codesign --verify`, and Launch Services `open -a` smoke.
- App/page/package actually opened: `/Applications/Mudsnote.app` opened isolated `.md` and `.markdown` files during cold and warm app states.
- Result: All 165 tests passed. Installed-app accessibility showed the requested Markdown content, and Command-S updated the original `.markdown` path without creating a renamed file or showing a save panel.
- Not verified: changing the user's default Finder association to Mudsnote, because the app intentionally registers as an alternate editor.

## Decisions

- External Markdown files open in separate editor windows and remain at their original paths.
- Mudsnote registers as an alternate Markdown editor rather than forcibly replacing the user's default app.

## Next

- None for this scope.
