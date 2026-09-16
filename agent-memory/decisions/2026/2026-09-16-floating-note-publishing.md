# Floating note publishing

Scope: macOS, file-backed floating editors only. Quick capture and unbound floating
notes retain draft-only behavior. No schema migration or bulk note rewrite.

The blank library document was real: creation wrote an empty Markdown file, while
subsequent floating edits only wrote Drafts snapshots. Publish these edits through
the existing serial background queue using coordinated, expected-content writes.
Keep the draft on disk until publication succeeds. Keep filenames stable during
autosave; update the controller baseline after success. Coalesced snapshots use
the last committed baseline, rather than an older UI snapshot. External changes
use the existing conflict-copy behavior, preserving both versions. Clear cached
baselines when explicitly loading another floating document.

Risk review: write failures retain recoverable snapshots and keep the editor open.
Empty edits to an existing file publish an empty document instead of deleting the
draft alone. Manual save flushes queued publication before its normal save/close
path. Restored drafts schedule publication when shown. No user content belongs in
tests or this record; test fixtures use temporary files and isolated defaults.

Regression coverage: an already-open library receives the floating document via
its file-change refresh path; repeated writes do not self-conflict; real external
changes preserve both bodies; failed writes retain the recoverable draft.

Verification: 320 tests passed, plus all 8 Release performance tests. After the
window-registry adjustment the 320-test macOS PR gate passed again. The signed
installed candidate was verified through the real floating editor and library:
an existing empty note recovered its complete draft through normal app opening,
published successfully, and appeared with title, body, list preview, and tab title
in the already-open library. A local recovery copy was retained before opening.
The floating window remained open. No iOS build or installation was performed.
