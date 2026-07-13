# Library accessibility semantics

## Request

Continue Apple Notes parity with native interaction quality and no unnecessary visual weight.

## Baseline

- Branch: `main`
- HEAD: `ba9b61f`
- Dirty files before work: none

## Changes

- Added accessibility names for the source surface, note list, search scope, title field, editor body, and modification date.
- Excluded visual source-count labels from the accessibility tree.
- Exposed source counts as values on their actionable source buttons.

## Verification

- Focused library-window accessibility assertions passed.
- `swift test` passed.
- `git diff --check` passed.
- Packaged, strictly signature-verified, and launched `/Applications/Mudsnote.app`.
- Side-by-side QA: `/tmp/mudsnote-library-accessibility-179/apple-notes-vs-mudsnote.png`; no visible regression.

## Decisions

- Keep visual metadata and accessibility navigation concise by attaching counts to the source action rather than exposing duplicate text nodes.

## Next

- Continue P4 edge-state and keyboard/VoiceOver verification against the installed app.
