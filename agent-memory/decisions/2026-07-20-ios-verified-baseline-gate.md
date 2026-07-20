# iOS verified baseline gate

## Context

The accepted iOS UI and a later launch-performance change lived in separate Draft PRs. New work started from `main`, which was Git-current but did not contain the accepted product state. CI could validate each branch independently without detecting that regression.

## Decision

- `.devflow-baselines.json` owns the machine-readable iOS acceptance marker and high-coupling paths.
- Every iOS Devflow task starts with `--track ios`.
- The configured `verified_commit` must be an ancestor of the chosen base.
- Open PRs touching protected paths block a parallel task. Prefer merging/closing the upstream PR or stacking from its head; an overlap override requires explicit review and remains recorded in task state.
- Update the marker only after the accepted implementation is merged and the required real-artifact verification is complete.

## Consequences

Task startup may pause earlier when old iOS PRs remain open. That early stop is intentional: resolving integration before implementation avoids UI rollback, repeated large-file reads, conflict repair, and duplicate full validation later.
