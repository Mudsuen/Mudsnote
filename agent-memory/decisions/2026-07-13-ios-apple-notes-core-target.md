# 2026-07-13 iOS Apple Notes core target

## Context

The iOS companion was capture-first. The user has now explicitly expanded its goal
to the core Apple Notes product experience, except features that do not fit Mudsnote
such as phone-call recording and collaboration share links.

## Decision

- Use Apple Notes' core information architecture and everyday note lifecycle as the
  iPhone baseline.
- Keep local Markdown and user-authorized iCloud Drive folders as the data boundary.
- Make Mudsnote capture the replacement for ordinary New Note and Quick Note entry.
- Route every capture entry through one durable capture pipeline; saved notes then
  participate in one standard library/editor lifecycle.
- Support iPhone only. Do not spend product or verification effort on iPad.
- Exclude Apple-private database integration, phone-call recording, collaboration,
  shared folders, and share-link permissions.

## Consequences

The iOS app is no longer merely a companion capture console. Folder, list, editor,
search, trash, move, pin, attachment, and recovery behavior are first-class product
work. UI parity must follow the storage lifecycle rather than creating view-local
state or a second note model.

The detailed delivery and acceptance checklist lives in
`docs/ios-apple-notes-parity-roadmap.md`.
