# 2026-07-13 iOS editor photo attachments

## Request

Continue the Notes-style iPhone editor toward complete editing while preserving
ordinary local Markdown files and Mudsnote attachment conventions.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `3e74f08`

## Changes

- Added a Photos picker to the document editor's single horizontal formatting bar.
- Saves selected images under `Attachments/yyyy/mm` and inserts a relative Markdown
  image reference into the open document.
- Flushes any pending text autosave before attaching an image, keeping the document
  and attachment transaction ordered.
- Generates numbered attachment names when two images share the same timestamp.
- Uses no-overwrite writes so an existing attachment is never replaced.
- Rolls back a newly written image if the Markdown document changed externally or
  the document update otherwise fails.
- Refreshes document, list metadata, attachment inventory, and active search results
  after a successful attachment.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused actor test passed for insertion, same-timestamp collision handling, and
  conflict rollback.
- Full App and UI suite: 57 passed, 0 failed, 0 skipped.
- UI automation confirms the image picker entry is present in the expanded editor.
- One iPhone 17 Pro / iOS 26.5 simulator was explicitly booted to SpringBoard ready,
  used with parallel testing disabled, and shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteEditorAttachmentFocusedRetry.xcresult`
  - `/tmp/MudsnoteEditorAttachmentFullFinal.xcresult`

## Decisions

- Attachment files are written before the Markdown reference and removed on any
  failed document commit, preventing broken references and orphan files.
- The attachment path remains relative and portable; no Photos library identifier or
  proprietary database record is stored.

## Next

- Add rendered attachment removal and move normal editing away from exposed raw
  Markdown syntax while retaining an advanced Markdown source path.
