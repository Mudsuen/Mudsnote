# iOS note PDF export

## Request

Continue the iPhone Apple Notes parity goal while retaining Mudsnote's Markdown, New Note, and Quick Note advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `47751e2` (`Support PDF markup on iPhone`).
- Dirty files before work: none; the first deliberate change was baseline screenshot retention in the existing note-options UI test.

## Product audit

- Captured the opened-note options menu on iPhone 17 Pro / iOS 26.5 and reviewed Apple's current Notes export and print guidance.
- Apple Notes exposes PDF export and printing for an opened note. Mudsnote only shared the portable Markdown file, so print-ready PDF export was the highest-impact remaining local, non-collaborative, non-table gap selected for this iteration.
- Compared the baseline menu, final menu, native share sheet, and the rendered first PDF page. Visual inspection caught and fixed dynamic dark-mode text colors that initially became invisible on white PDF paper.

## Changes

- Open document notes now offer `Export as PDF` beside `Share Note` and `Find in Note`.
- A dedicated core exporter creates a derived Letter-size PDF with stable margins, title, modified date, rendered inline Markdown, headings, links, attachment names, readable portable-table rows, and multi-page pagination.
- A leading Markdown heading matching the file title is deduplicated in the PDF only; the Markdown source is never rewritten.
- Export uses explicit print-safe black, gray, and link colors, independent of the app's light or dark appearance.
- The native share sheet exposes Preview, Markup, Print, Save to Files, and other installed local activities.
- Export progress, failure recovery, safe filenames, English/Simplified Chinese copy, and atomic temporary-file output were added.
- The exporter lives in `Core/NotePDFExporter.swift`; the reader only owns presentation state and invokes the service.
- Existing Markdown source sharing, PDF attachment markup, Quick Capture, New Note, search, and iPhone table-authoring scope remain unchanged.

## Verification

- Focused paginated PDF and system-share UI coverage passed.
- The generated fixture PDF was opened outside the app renderer: metadata named `UI Lifecycle`, page geometry was 612 x 792 points, black/gray body text was visible on white paper, links remained blue, attachments occupied separate rows, and the existing portable Markdown table remained readable without adding table authoring.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5, simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`: 154/154 passed, zero failures and zero skipped (105 unit tests and 49 UI tests).
- Parallel testing remained disabled and no additional simulator was booted.
- Generic iOS Release archive succeeded at version `1.0 (1)` with no warning or error.
- App and Widget passed strict code-sign verification; the app privacy manifest was embedded; App Intents SSU resources were generated for English and Simplified Chinese.
- Physical device `MudsPhone` / iPhone Air remained listed as `unavailable`; the final installation attempt returned CoreDevice error 1011 before reaching the phone.

## Storage

- Peak removable iteration storage was about 573 MiB: 353 MiB test DerivedData, 191 MiB archive DerivedData, 21 MiB archive, about 8 MiB extracted visual evidence, plus small logs and rendered pages.
- The sole used simulator was shut down and all iteration-specific temporary artifacts were removed after verification.

## Next

- Continue the next highest-impact iPhone Notes parity gap while preserving portable Markdown, PDF export/print, native PDF attachment markup, the single-row Quick Capture layout, and the current iPhone-only/no-new-table scope.
