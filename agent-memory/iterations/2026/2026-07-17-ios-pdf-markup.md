# iOS PDF markup

## Request

Continue the iPhone Apple Notes parity goal while retaining Mudsnote's Markdown, New Note, and Quick Note advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `2bf2783` (`Support video attachments on iPhone`).
- Dirty files before work: none.

## Product audit

- Captured the existing generic Quick Look attachment flow on iPhone 17 Pro / iOS 26.5 and reviewed Apple's current Notes PDF and scanned-document guidance.
- Apple Notes lets an iPhone user open, edit, and mark up PDFs inside a note. Mudsnote already stored scans as portable PDFs but opened every attachment read-only, so writable PDF markup was the highest-impact remaining non-table gap selected for this iteration.
- Inspected the baseline read-only preview, active native PencilKit tools, and the same PDF reopened with its test stroke still present. A same-viewport before/after comparison confirmed one clean close control, a centered title, the native editing tool group, and no duplicate or overlapping controls.

## Changes

- Scanned and imported PDFs now open in a true modal `QLPreviewController` with native Markup and PencilKit tools; generic files remain read-only Quick Look previews.
- A stable Notes-style close action dismisses the presented navigation controller first, allows Quick Look to finish its asynchronous PDF update, and only then commits the edited preview.
- Attachment previews are bounded temporary copies with a SHA-256 baseline. PDF writes are coordinated, atomic, constrained to `Attachments`, invalidate library/search caches, and reject an external edit made after the preview opened.
- Closing an unchanged PDF performs no write and shows no false saved status.
- Reader and attachment-browser entry points share the same preview and save architecture.
- English and Simplified Chinese save, unsupported-editing, and external-conflict copy was added to the shared String Catalog.
- The UI fixture now contains a real one-page PDF so automation exercises system PDF rendering rather than a text file with a PDF suffix.
- Existing Markdown rendering, search, Quick Capture, full editing, video/audio/image attachments, and iPhone table behavior remain unchanged.

## Verification

- Focused preview, path-safety, atomic-commit, generic read-only, and PDF markup coverage passed: 4/4.
- The real draw, close, save, and reopen PDF UI flow passed five consecutive stress iterations.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5, simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`: 152/152 passed, zero failures and zero skipped.
- Parallel testing remained disabled and no additional simulator was booted.
- Generic iOS Release archive succeeded at version `1.0 (1)` with no warning or error.
- App and Widget passed strict code-sign verification; the app privacy manifest was embedded; App Intents SSU resources were generated for English and Simplified Chinese.
- Physical device `MudsPhone` / iPhone Air remained visible to CoreDevice but `unavailable`; the final installation attempt returned CoreDevice error 1011 before reaching the phone.

## Storage

- Peak removable iteration storage was about 1.4 GiB because repeated race diagnosis retained 734 MiB test DerivedData, three 191 MiB archive DerivedData directories, three 21 MiB archives, 29 MiB visual audit evidence, and 4.3 MiB logs at once.
- The sole used simulator was shut down and all iteration-specific temporary artifacts were removed after verification.

## Next

- Continue the next highest-impact iPhone Notes parity gap while preserving portable Markdown, native PDF markup persistence, the single-row Quick Capture layout, and the current iPhone-only/no-new-table scope.
