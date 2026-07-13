# 2026-07-13 bounded source scope projection

## Request

Continue Mudsnote toward Apple Notes parity while keeping the architecture lightweight and optimizing large-library interaction performance.

## Baseline

- Branch: `main`
- HEAD: `91cb88d`
- Dirty files before work: seven concurrent iOS companion files; no macOS or documentation changes.

## Changes

- Added a reusable bounded sequence projection to `LibraryNoteListProjection`.
- Changed Inbox, folder, and tag navigation to stop after collecting the 240 visible notes instead of filtering and allocating every match in the 10,000-note snapshot.
- Preserved the snapshot's modified-date order and existing source semantics.
- Added a regression that proves 240 alternating matches inspect only the first 479 inputs and that a zero limit never evaluates the predicate.

## Verification

- Commands run: `swift test --filter boundedNoteProjectionStopsAfterReachingItsLimit`, `swift test`, `./scripts/package_app.sh`, `codesign --verify --deep --strict /Applications/Mudsnote.app`, and `./scripts/library_smoke.sh`.
- App/page/package actually opened: the isolated smoke launched `/Applications/Mudsnote.app` against a temporary library.
- Result: focused regression passed; all 155 tests passed; production packaging, strict signature verification, and the complete installed-app library smoke passed.
- Not verified: no new visual capture was needed because this iteration does not change layout, rendering, or control state.

## Decisions

- Keep bounded scope filtering in the existing pure note-list projection instead of adding another controller or cache layer.
- Search ranking still considers its complete candidate scope; this optimization applies only to empty-query source navigation where visible order already follows the snapshot.

## Next

- Continue auditing bounded main-thread list work, especially non-default global sort behavior, without weakening complete search ranking.
