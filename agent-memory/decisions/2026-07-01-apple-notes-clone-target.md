# 2026-07-01 Apple Notes clone target

## Context

The user provided an Apple Notes desktop screenshot and set the ongoing Mudsnote target to "复刻 Apple Notes".

## Decision

Mudsnote's desktop main window should iterate toward Apple Notes parity while preserving the app's lightweight, local-first Markdown identity.

Target desktop qualities:

- Direct open shows the library as the main workspace.
- Left column behaves like Apple Notes' account/folder/tag source list.
- Middle column behaves like Apple Notes' recency-grouped note list with selected cards.
- Right column behaves like a focused note editor with date/status metadata and direct rich editing.
- Search, new note, folder/tag filters, save, and open-in-separate-window remain functional.

Non-goals:

- Do not turn Mudsnote into iCloud Notes or a database-backed sync product.
- Do not remove quick capture, floating notes, or plain Markdown storage.
- Do not chase every Apple Notes toolbar item before the core library/editor workflow is solid.

## Consequences

Future desktop UI work should compare against Apple Notes' three-column layout first. iOS companion work remains capture-first unless the user explicitly asks for mobile editor parity.
