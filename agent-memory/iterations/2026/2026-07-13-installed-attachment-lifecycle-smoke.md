# Installed attachment lifecycle smoke

## Request

Continue Apple Notes parity with stronger installed-app evidence for core editor workflows.

## Baseline

- Branch: `main`
- HEAD: `ac8e7a0`
- Dirty files before work: none

## Changes

- Extended the isolated installed-app library smoke with a real Finder-file paste into the moved note.
- Verified attachment copying under the note folder's `Attachments/yyyy/mm` directory and portable relative Markdown serialization.
- Used the editor's Accessibility object-replacement character and the list row's "有附件" image description as native rendering evidence.
- Relaunched the packaged app against the same isolated library and verified the saved attachment renders again.

## Verification

- `bash -n scripts/library_smoke.sh`, full `swift test`, and `git diff --check` passed.
- Packaged and strictly signature-verified `/Applications/Mudsnote.app`.
- Final installed smoke: `/tmp/mudsnote-installed-library-smoke-185-final`, including `attachment_reload=passed`.
- Content-state visual QA: `/tmp/mudsnote-attachment-smoke-visual-185/apple-notes-vs-mudsnote.png`; no toolbar, pane, or editor-layout regression.

## Decisions

- Exercise the public Finder paste workflow rather than bypassing the UI with a test-only attachment hook.
- Require filesystem, Markdown, immediate UI, and post-relaunch UI evidence for installed attachment coverage.

## Next

- Continue with deeper Apple Notes interaction and visual parity now that the main installed editor lifecycle is covered.
