# 2026-07-10 local attachment paste

## Request

Continue the active Apple Notes parity goal with lightweight, local-first editing behavior and installed-app verification.

## Baseline

- Branch: `main`
- Feature work began from clean HEAD `25b79ae`.
- The separate visual-QA privacy cleanup `da722dc` was committed while this iteration remained in progress.

## Changes

- Added shared attachment payload parsing for Finder file URLs, clipboard PNG data, and clipboard images convertible to PNG.
- Centralized local attachment storage under `Attachments/yyyy/mm`, conflict-safe naming, relative URL encoding, image detection, and Markdown label escaping.
- Added Finder multi-file and clipboard-image paste to both the Notes-like library editor and floating editor.
- Routed exact `Command-V` key equivalents through the Markdown editor before AppKit fallback, while preserving plain-text paste normalization.
- Added immediate native image/file rendering for unsaved notes through a synthetic note base URL.
- Reserved the internal `Attachments` directory for implementation data and excluded it from source-list folder enumeration and recursive note indexing.
- Added regression coverage for attachment parsing, keyboard paste routing, local copies, Markdown serialization, library save, floating-editor behavior, source-list hiding, and index exclusion.

## Verification

- Commands run:
  - `swift test --filter libraryAndFloatingEditorsPasteFilesAndImagesAsLocalMarkdownAttachments`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `codesign --verify --deep --strict /Applications/Mudsnote.app`
- Result:
  - Final full test run passed: 113 tests across 2 suites, including internal-directory source-list and index exclusion.
  - Installed `/Applications/Mudsnote.app` copied a Finder-selected PNG and PDF into `/tmp/mudsnote-paste-qa-20260710/Notes/Attachments/2026/07`.
  - The saved note contained standard relative Markdown for both files.
  - A full app restart reloaded the inline image, file chip, and note-list thumbnail from disk.
  - The final installed-app accessibility tree showed no `Attachments` source row after reloading the same note.
  - Reload evidence: `/tmp/mudsnote-paste-qa-20260710/reloaded.png`.
  - Strict code-signature verification passed.
- Not verified:
  - Structured HTML rich-text paste remains intentionally open.
  - iOS remains outside the active macOS parity goal.

## Decisions

- Keep clipboard semantics local-first: copy assets into the note library rather than retaining external security-scoped or transient pasteboard references.
- Treat the attachment directory as internal storage, not as a user folder or searchable note root.
- Verify paste through the installed app's real `Command-V` path, not only direct parser/controller calls.

## Next

- Continue with the next highest-impact Apple Notes workflow gap after completing the final full test/package pass.
