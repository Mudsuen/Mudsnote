# Platform verified baseline gate

## Context

An accepted platform UI can remain in a Draft PR while a later task starts from `main`. The branch may be Git-current but still omit the accepted macOS or iOS product state, and CI can validate the isolated branch without recognizing the regression.

## Decision

- `.devflow-baselines.json` owns separate machine-readable `macos` and `ios` acceptance markers and high-coupling paths.
- Every platform Devflow task starts with `--track macos` or `--track ios`.
- The selected platform's `verified_commit` must be an ancestor of the chosen base.
- Open PRs touching that track's protected paths block a parallel task. Prefer merging/closing the upstream PR or stacking from its head; an overlap override requires explicit review and remains recorded in task state.
- Update only the affected platform marker after its accepted implementation is merged and the required real-artifact verification is complete.

## Consequences

Task startup may pause earlier when old platform PRs remain open. That early stop is intentional: resolving integration before implementation avoids UI rollback, repeated large-file reads, conflict repair, and duplicate full validation later. Independent markers also allow one platform to advance without falsely claiming that the other was re-verified.
