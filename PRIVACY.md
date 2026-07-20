# Privacy

Mudsnote is local-first. Notes are stored as plain Markdown files in folders you choose.

## What Mudsnote Stores

- Markdown notes on disk
- User preferences
- Optional AI provider settings

## AI Data Flow

AI features are disabled by default. When enabled, Mudsnote sends text only after you explicitly invoke an AI command from the editor context menu or a slash command.

- Selection actions send only the selected text.
- Paragraph actions send only the current paragraph.
- Whole-note actions send only the active note content.
- AI commands run through the signed-in Codex runtime on this Mac in an ephemeral, read-only session.
- AI output is saved only if you choose to apply it.

Mudsnote does not perform background AI indexing, telemetry, analytics, or automatic note uploads.
