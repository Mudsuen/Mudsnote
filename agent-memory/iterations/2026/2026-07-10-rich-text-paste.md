# 2026-07-10 rich text paste

## Request

Continue the active Apple Notes parity goal after local attachment paste, preserving the compact toolbar/window baseline and keeping the editor lightweight and Markdown-backed.

## Baseline

- Branch: `main`
- HEAD: `b9b5ee8`
- Dirty files before work: none.
- Latest content comparison: `/tmp/mudsnote-visual-qa-20260710-after-paste/apple-notes-vs-mudsnote.png`.

## Changes

- Re-ran content-state visual QA and preserved the compact toolbar/window geometry because the comparison did not justify enlarging the user-approved baseline.
- Added an AppKit-backed HTML/RTF clipboard reader without adding a package dependency or alternate document model.
- Normalized imported headings, bold, italic, underline, strikethrough, links, bullet lists, numbered lists, and fixed-width runs into portable Markdown.
- Re-rendered normalized Markdown through the existing rich editor codec so imported content uses the same native visual semantics and save path as authored content.
- Added exact `Command-V` coverage and paragraph-boundary insertion when rich text is pasted beside existing content.
- Kept Finder file URLs first in attachment routing, pure clipboard images local-first, and rich text ahead of incidental image flavors.
- Enabled the same rich paste path in the library, quick-capture, floating, and separate-note editors through the shared `MarkdownTextView`.

## Verification

- Commands run:
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-20260710-after-paste`
  - `swift test --filter commandPasteNormalizesHTMLFormattingIntoPortableMarkdown`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `codesign --verify --deep --strict /Applications/Mudsnote.app`
- Result:
  - Final full test run passed: 114 tests across 2 suites.
  - Installed `/Applications/Mudsnote.app` accepted a system clipboard carrying HTML and plain-text flavors through real `Command-V`.
  - Autosave produced `/tmp/mudsnote-rich-paste-qa-20260710/Notes/2026-07-10-rich-paste-qa.md` with a heading, bold, italic, link, bullet list, and numbered list in plain Markdown.
  - A full app restart reloaded the same visible rich formatting from disk.
  - Paste screenshot: `/tmp/mudsnote-rich-paste-qa-20260710/pasted.png`.
  - Reload screenshot: `/tmp/mudsnote-rich-paste-qa-20260710/reloaded.png`.
  - Strict code-signature verification passed.
- Not verified:
  - RTF uses the same parser path and is covered structurally but the installed smoke seeded HTML rather than a live TextEdit copy.
  - Embedded images inside an HTML/RTF selection remain open; standalone images and Finder files are already handled by the local attachment path.
  - iOS remains outside the active macOS parity goal.

## Decisions

- Use AppKit's structured document import instead of parsing HTML strings manually.
- Keep normalization one-way into the established Markdown model; do not retain HTML/RTF or introduce proprietary rich storage.
- Treat real shortcut routing, insertion boundaries, saved Markdown, and restart rendering as one acceptance path.

## Next

- Continue with a measured toolbar/source-list visual delta or the next remaining everyday editor workflow after this commit.
