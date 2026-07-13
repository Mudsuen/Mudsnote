# 2026-07-13 iOS rendered attachment removal

## Request

Continue complete Notes-style document editing while retaining Markdown attachment
references and a user-owned attachment library.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `2e63f5c`

## Changes

- Added a destructive `Remove from Note` context action to rendered images, audio,
  and file attachments.
- Removes the exact attachment line through optimistic document saving, so an
  external edit cannot be overwritten.
- Refreshes the rendered document, note list metadata, and active search after
  removal.
- Preserves the underlying attachment file because other Markdown notes may share
  the same relative reference; it remains available in the attachment library.
- Added localized success and recovery messages.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused actor test passed for insertion, same-timestamp collision, rendered
  reference removal, preserved attachment files, and conflict rollback.
- Full App and UI suite: 57 passed, 0 failed, 0 skipped.
- One explicitly booted iPhone 17 Pro / iOS 26.5 simulator was used with parallel
  testing disabled and shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteEditorAttachmentRemovalFocused.xcresult`
  - `/tmp/MudsnoteEditorAttachmentRemovalFull.xcresult`

## Next

- Continue replacing whole-document raw source editing with rendered block editing,
  while retaining a separate advanced Markdown source path.
