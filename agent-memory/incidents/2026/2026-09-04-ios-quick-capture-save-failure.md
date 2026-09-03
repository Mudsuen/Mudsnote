# 2026-09-04 iOS quick-capture save failure

## Failure

iOS quick capture again presented “Couldn’t Save Quick Note” while saving to the
selected Markdown library. The original alert intentionally hides the
underlying filesystem error, so the exact provider error from the user's
occurrence was not recoverable after the fact.

## Cause

The storage audit found four independently unsafe boundaries:

- Foreground capture used only a direct write, even though shortcut capture
  already had a durable pending queue.
- The direct write mutated children of a File Provider directory without
  coordinating the existing parent directory.
- Persisted folder bookmarks used the legacy empty option set and callers
  treated a failed security-scope acquisition as usable.
- Capture filenames were limited by character count rather than UTF-8 byte
  count, allowing emoji or other multibyte titles to exceed provider component
  limits.

The old interrupted-write UI fixture filled the pending queue, so it no longer
failed at the production foreground-write boundary and did not detect this
regression.

## Recovery

- Keep the normal foreground path direct and coordinate the selected existing
  directory while writing attachments and the Markdown note.
- Validate security-scoped access before saving, store minimal bookmarks, and
  migrate legacy bookmarks after successful resolution.
- Bound generated filename stems by UTF-8 bytes.
- If direct creation fails, reserve the same portable capture in the durable
  queue. Dismiss the composer only after that queue commit succeeds. If both
  paths fail, keep the draft open with the recovery action.
- Log only filesystem error domain and code so future incidents are diagnosable
  without recording note contents or private paths.

## Verification

- The fault-injected foreground save moved into the queue, dismissed without
  the error card, then replayed into a real Markdown file.
- Normal direct saves, duplicate concurrent captures, damaged-queue isolation,
  bookmark migration, and an 80-emoji title passed focused regressions.
- The complete iOS unit suite and unsigned generic iOS Release build passed.
