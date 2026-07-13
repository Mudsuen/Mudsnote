# Nonblocking cached-note validation

## Problem

The loaded-note cache avoided Markdown parsing and rendering during repeated navigation, but its hit path still called `attributesOfItem` synchronously on the main actor to validate the file modification date. A slow metadata read could therefore block arrow-key selection before cached content appeared.

## Change

- Cache lookup now reads only the bounded in-memory cache and applies the cached document immediately.
- File modification-date validation runs in a detached utility task through an injectable loader.
- Unchanged files end validation without another Markdown read.
- Changed files reload off the main actor and replace the editor only when task cancellation, selection generation, and selected-path checks still pass.
- Dirty editor state rejects a delayed external reload so unsaved edits are never overwritten.
- Added a regression with a `350ms` metadata probe that requires the synchronous selection path to complete within `150ms` and records that metadata access never reaches the main thread.
- Updated the external-edit cache test to await the asynchronous validation contract.

## Verification

- Focused cached-navigation, external-edit, and arrow-key tests passed: 3 tests.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was repackaged and passed strict code-signature verification.
- Installed create/save/search/trash/restore/move/attachment/relaunch smoke passed at `/tmp/mudsnote-library-smoke-190`.

## Durable rule

A cached interaction path must not synchronously touch the filesystem for freshness checks. Keep immediate rendering separate from asynchronous validation, and guard the entire validation/reload result against newer selection and unsaved editor state.
