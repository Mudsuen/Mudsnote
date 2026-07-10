# 2026-07-10 attachment Quick Look

## Request

Continue Apple Notes parity with higher-impact editing functionality rather than exact color matching. Keep the implementation native and lightweight.

## Baseline

- Branch: `main`
- HEAD before work: `bf09f01 Keep library navigation off main thread`
- Dirty files before work: none
- Local file attachments rendered as compact editor cards and supported open/reveal/copy actions, but they had no native preview workflow.

## Changes

- Added a shared system `QLPreviewPanel` coordinator for local attachments.
- Added `快速查看` as the first attachment context-menu action with the standard Space key equivalent.
- A selected attachment, or a caret immediately before/after it, now opens Quick Look when Space is pressed.
- Applied the same behavior to the library editor and floating note editor.
- Kept ordinary Space input unchanged when the selection is not on an attachment.
- Dismissed controller-owned Quick Look panels when their editor window closes.
- Bound the panel data source after it becomes key, then reloaded and selected item `0`; this avoids Quick Look's responder-chain controller refresh clearing the preview item.

## Verification

- Passed targeted library and floating-editor attachment tests.
- Added coverage for attachment selection lookup, context-menu order and key equivalent, Space interception, preview URL, and non-attachment Space passthrough.
- Passed: `swift test` with 109 tests.
- Passed: `git diff --check`.
- Passed: `./scripts/package_app.sh` and installed `/Applications/Mudsnote.app`.
- Installed-app smoke used only `/tmp/mudsnote-attachment-qa-20260710` with a single `Attachment QA` note and generated local PDF.
- Computer Use selected the attachment from the editor, pressed Space, and confirmed the Quick Look accessibility tree contained the PDF document and text `Attachment QA` / `System Quick Look preview`.
- Visual inspection confirmed the PDF page rendered inside the system Quick Look panel instead of showing `未选定项目`.
- The isolated app instance was closed and the normal installed Mudsnote app was reopened after verification.

## Decisions

- Use native Quick Look instead of building an in-app preview stack or adding a dependency.
- Keep double-click Open as a separate action; Space is preview and does not launch the file's default app.
- Do not use real user notes for attachment smoke fixtures.

## Next

- Continue deeper attachment preview types or table editing, depending on the next highest-impact Apple Notes workflow gap.
