# iOS photo and video attachments

## Request

Continue the iPhone Apple Notes parity goal while retaining Mudsnote's Markdown, New Note, and Quick Note advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `322dd6c` (`Insert camera-scanned text into notes`).
- Dirty files before work: none.

## Product audit

- Captured the existing Quick Capture attachment menu on iPhone 17 Pro / iOS 26.5 and reviewed Apple's current Notes attachment guidance.
- Apple Notes lets an iPhone user add a photo or video from the attachment flow. Mudsnote's corresponding Quick Capture and full-editor flows were image-only, so the highest-impact non-table gap selected for this iteration was portable video attachment support.
- Captured the final attachment menu and attachment browser, then inspected the baseline and final Quick Capture states side by side at the same 1206 x 2622 viewport.
- The final menu remained one vertical menu and the capture toolbar remained one row; no second toolbar row or unrelated visual system was introduced.

## Changes

- Quick Capture and the full editor now select both photos and videos from Photos and capture either medium-quality photos or videos with the camera.
- Imported or captured videos are validated as bounded semantic video attachments, survive Quick Capture recovery, and are written to the authorized Markdown library with portable `[Video](Attachments/...)` references and a `#视频` attachment tag.
- Open notes render local video references inline with the native video player; leaving the player pauses playback.
- The attachment browser recognizes videos, exposes a dedicated Videos filter and section, and keeps the existing exact-owner navigation behavior.
- Generic file import recognizes movie files and applies the video size policy instead of the smaller generic-file policy.
- Video attachments are limited to 50 MiB and one draft remains limited to 64 MiB so pending queue encoding stays below its existing bound.
- English and Simplified Chinese attachment, media, and failure copy was added to the shared String Catalog.
- Existing image, document, scan, drawing, audio, Markdown editing, Quick Note, and table behavior remained unchanged.

## Verification

- Focused video, recovery, Quick Capture menu, full editor, and attachment-browser coverage passed: 7/7.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5, simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`: 150/150 passed, zero failures and zero skipped.
- Parallel testing remained disabled and no additional simulator was booted.
- Generic iOS Release archive succeeded at version `1.0 (1)` with no warning or error.
- App and Widget passed strict code-sign verification; the app privacy manifest was embedded; App Intents SSU resources were generated for English and Simplified Chinese.
- Physical device `MudsPhone` / iPhone Air remained visible to CoreDevice but `unavailable`; the single installation attempt returned CoreDevice error 1011 before reaching the phone.

## Storage

- Peak removable iteration storage was about 616 MiB: 383 MiB test DerivedData, 190 MiB archive DerivedData, 21 MiB archive, 7.4 MiB audit screenshots, and less than 1 MiB logs.
- The sole used simulator was shut down and all iteration-specific temporary artifacts were removed after verification.

## Next

- Continue the next highest-impact iPhone Notes parity gap while preserving portable Markdown, single-row Quick Capture, video attachment behavior, and the current iPhone-only/no-new-table scope.
