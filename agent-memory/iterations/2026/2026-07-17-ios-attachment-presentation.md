# iOS Notes-style attachment presentation

## Request

Continue the iPhone Apple Notes parity goal while retaining Mudsnote's Markdown, New Note, and Quick Note advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `7d157b9` (`Export notes as PDF on iPhone`).
- Dirty files before work: none.
- Only iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was booted; parallel testing stayed disabled.

## Product audit

- Captured the opened-note options baseline and reviewed Apple's current iPhone Notes attachment-view guidance.
- Apple Notes supports Small, Large, and Plain Link for one attachment, plus whole-note Small/Large presentation. Mudsnote always rendered the large representation, which crowded a half-sheet note and was the highest-value remaining local attachment interaction gap.
- Captured the final per-item View As menu and compact attachment card, then inspected a three-state baseline/final comparison at the same iPhone viewport.
- Visual evidence: `/tmp/mudsnote-ios-attachment-view-audit/05-baseline-final-comparison.png`.

## Changes

- Long-pressing any rendered attachment now exposes View As > Small, Large, or Plain Link while preserving open, share, rename, and remove actions.
- Note Options now exposes Attachment View > Set All to Small or Set All to Large when the note contains attachments.
- Small mode uses a compact, tappable Notes-style card with a real thumbnail or system file icon; Plain Link remains a minimal tappable file reference; Large preserves the existing inline media behavior.
- Per-note defaults and per-attachment overrides persist in UserDefaults without modifying Markdown.
- Preferences migrate across note rename/move, folder rename/move, batch move, and attachment rename; removal and permanent deletion clean stale values.
- English and Simplified Chinese copy was added to the existing String Catalog.
- No table-authoring, iPad, or dedicated accessibility scope was added.

## Verification

- Focused lifecycle unit coverage and the new attachment-presentation UI flow passed.
- The existing attachment context-menu and attachment-library return-to-note UI tests were run beside the new test after a compatibility regression was found and fixed; all three passed together.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5: 156/156 passed, zero failures and zero skipped (106 unit tests and 50 UI tests).
- Generic iOS Release archive succeeded at version `1.0 (1)`.
- App and Widget passed strict code-sign verification; the privacy manifest, App Intents metadata, and English/Simplified Chinese SSU resources were embedded.
- Physical device `MudsPhone` / iPhone Air remained listed as `unavailable`; the Release installation attempt returned CoreDevice error 1011 before reaching the phone.

## Storage

- Peak removable iteration artifacts were about 600 MiB: 290 MiB test DerivedData, 191 MiB archive DerivedData, 22 MiB archive, and 97 MiB audit results/evidence.
- DerivedData, archives, xcresults, and simulator runtime state are removed after verification; only the small accepted PNG audit evidence is retained in `/tmp` for this handoff.

## Next

- Continue the next highest-impact iPhone Notes parity gap while preserving portable Markdown, per-note attachment density, the single-row Quick Capture layout, and the current iPhone-only/no-new-table scope.
