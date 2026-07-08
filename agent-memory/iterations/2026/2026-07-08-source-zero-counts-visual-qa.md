# 2026-07-08 source zero counts visual QA

## Request

Continue the active Apple Notes parity goal for Mudsnote, keeping the macOS library UI moving closer to Apple Notes while preserving lightweight local Markdown behavior.

## Baseline

- Branch: `main`
- HEAD before work: `bdffda7 Match Notes empty new note editor`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-empty-new-note-editor-verified/apple-notes-vs-mudsnote.png` showed a much sparser source list than the Apple Notes reference, partly because the visual QA fixture only exposed one local notes directory.

## Changes

- Added repeatable `--visual-qa-extra-dir` launch arguments so the visual QA harness can open the app with multiple real local folders.
- Updated the visual QA fixture to create real `Resources` and `Archives` directories alongside `Notes`.
- Added one archived note and kept `Resources` empty so source-list zero-count behavior is visible in screenshot QA.
- Changed folder source rows to show `0` counts for empty visible folders, matching Apple Notes' source-list count treatment.
- Documented the empty-folder count rule in the parity roadmap.

## Verification

- Commands run:
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-zero-counts-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Full `swift test` passed with 98 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Visual QA captured `/tmp/mudsnote-visual-qa-source-zero-counts-final/apple-notes-vs-mudsnote.png`.
  - The raw app screenshot shows `Notes`, `Resources 0`, `Archives 1`, and `Recently Deleted 4` in the source list.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Keep Apple-private categories out of product code. Visual QA uses real local folders, not fake Apple service rows.
- Showing `0` for visible local folders is a lightweight UI rule and does not add scanning beyond the existing shared count snapshot.
- Keep the earlier compact, borderless editor-tools capsule as the toolbar baseline; do not re-expand the buttons or reintroduce a prominent light rim.

## Next

- Continue source-list hierarchy visual tuning and editor/date positioning after this more representative comparison state is verified.
