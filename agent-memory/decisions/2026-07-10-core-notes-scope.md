# 2026-07-10 core Notes scope

## Context

The desktop goal remains Apple Notes visual and interaction parity, but the user explicitly excluded non-core features such as call recordings and system sharing from the required scope.

## Decision

- Keep the core library, folders, tags, trash, search, pinned notes, editor, and local Markdown workflows.
- Omit the call-recordings smart source and its snapshot filters/counts.
- Keep the Notes-like file-actions toolbar shape, but limit it to local Markdown copy/export plus current-note actions.
- Do not treat system sharing or call-recording workflows as parity blockers.

## Consequences

The default source list and menus stay quieter, the controller carries fewer states, and count refreshes avoid an unused full-snapshot filter. Future parity work should prioritize visible library/editor behavior and measured performance rather than expanding into Apple Notes integrations that do not help local Markdown use.
