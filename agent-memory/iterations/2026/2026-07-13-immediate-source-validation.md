# Immediate source validation

## Request

Continue Apple Notes parity while keeping the architecture responsive and efficient.

## Baseline

- Branch: `main`
- HEAD: `9866304`
- Dirty files before work: none

## Changes

- Replaced the source-validation task's fixed `80ms` sleep with `Task.yield()`.
- Preserved snapshot-first painting, detached filesystem work, task cancellation, and generation guards.

## Verification

- The focused background-refresh test passed 10 consecutive runs.
- `swift test` passed after the change.
- `git diff --check` passed.
- Packaged, strictly signature-verified, and launched `/Applications/Mudsnote.app`.
- Visual QA: `/tmp/mudsnote-source-validation-yield-178/apple-notes-vs-mudsnote.png`; no visible layout regression.

## Decisions

- Use cancellation plus generation identity for source-validation coalescing instead of an artificial time debounce.

## Next

- Continue state-matched Apple Notes comparisons and address only evidence-backed visual or interaction gaps.
