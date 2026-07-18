# 2026-07-17 delivery workflow pilot

## Request

Review the shared Devflow process for safety and efficiency, then pilot the minimal delivery workflow in Mudsnote without touching app behavior or real user data.

## Baseline

- Branch: `codex/20260717-delivery-workflow-pilot`
- HEAD: `b06cfe6`
- Dirty files before work: none
- The formal local `main` was 47 commits ahead of `origin/main`; this task deliberately uses the reviewed remote baseline and does not publish those commits.

## Changes

- Added the project verification contract, stable PR CI, PR template, delivery documentation, and a minimal project-local Devflow pointer.
- Kept wall-clock performance gates in `full`; PR CI runs deterministic coverage only.

## Verification

- Commands run: `./scripts/verify pr`; `./scripts/verify full`; YAML and shell syntax checks
- App/page/package actually opened: not required for delivery-only changes
- Result: PR build plus 154 deterministic tests passed; Release build plus all 159 tests, including strict performance gates, passed
- Not verified: iCloud, real notes, Widget, sharing, physical device, and installed-app behavior

## Decisions

- PR CI must not touch real note data or credentials.
- Strict performance budgets belong on a controlled machine, not a shared PR runner.

## Next

- Merge only after CI and user review.
- Reconcile the 47 local `main` commits separately; they are outside this PR.
