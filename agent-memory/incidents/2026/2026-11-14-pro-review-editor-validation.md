# Editor review validation

Scope: macOS, based on `c97433940245090be86948d1d1a515151d26020e`.

The review fixes stale document operations, rich-text re-interpretation,
literal fenced/indented Markdown, source-mode insertion, search freshness,
attachment reference accounting, and graph viewport resets. Tag batches no
longer restore old snapshots after a failure: each write compares its source,
and a partial batch reports how many notes were changed.

Validation used isolated defaults, temporary notes, and the AppKit test runner.
Seven focused regressions passed. The first required macOS run exposed two
checklist-shortcut normalization regressions; source preservation now excludes
those editor shortcuts. An unrelated overview-card animation test also failed
in that run, then passed in isolation and in the final required run. No overview
animation code was changed. `./scripts/verify macos pr` finally passed all 422
tests. The dense-format serialization performance test passed separately.

This is not full CommonMark editing support. Indented/fenced blocks remain
literal rather than being destructively flattened. Attachment scanning protects
reference definitions, saved drafts and trash references; it does not establish
support for every external HTML/wiki-link syntax. AI provider execution and
physical device interoperability were not exercised. No iOS build or install
was performed.
