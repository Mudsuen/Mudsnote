# 2026-07-13 snapshot-backed Markdown serialization

## Request

Continue Apple Notes parity while making Mudsnote's architecture and editing performance as efficient as practical.

## Baseline

- Branch: `main`
- Starting HEAD: `6fd26e9`; concurrent iOS work advanced HEAD to `6053ff4` before this iteration committed
- Dirty files before work: concurrent iOS companion files, left untouched

## Changes

- Added one immutable `MarkdownRichTextCodec.SerializationContext` per serialization call.
- Reused a single `NSString` snapshot across paragraph, table, and inline-run serialization instead of bridging the full Swift string for every run.
- Cached `NSFontManager` traits by font object identity for the lifetime of that serialization.
- Added a 5,000-run dense-format regression that checks the complete Markdown output and a `<50ms` debug budget.

## Verification

- Baseline focused test: about `41ms`.
- Font-trait caching alone: about `39ms`.
- Shared immutable string snapshot plus trait cache: stable focused runs around `27ms`, with a cold run around `38ms`.
- Eight focused serialization, table, link, attachment, paste, and autosave tests passed.
- Full `swift test` passed.
- `./scripts/package_app.sh` installed `/Applications/Mudsnote.app`.
- `./scripts/library_smoke.sh /tmp/mudsnote-library-smoke-serialization-203` passed, including attachment reload.
- `codesign --verify --deep --strict /Applications/Mudsnote.app` passed.
- Content-state visual comparison passed at `/tmp/mudsnote-visual-qa-203-serialization/apple-notes-vs-mudsnote.png` with no intended UI change.

## Decisions

- Keep note-switch and explicit-save writes synchronous for durability; optimize serialization work before considering background persistence.
- Treat immutable Foundation bridging as a serialization-boundary concern, not per-run work.
- Keep the cache call-scoped so edits cannot invalidate shared state and memory cannot accumulate across saves.

## Next

- Continue complex editor-content parity, then profile remaining synchronous file-write cost separately from serialization.
