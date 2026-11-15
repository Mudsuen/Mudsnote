# macOS search verification — 2026-11-15

The search change was checked against baseline
`7bebf96370301a5977d7702d15d15e7d2084b407` using synthetic notes and isolated
UserDefaults suites. No CI check used the personal note library.

`./scripts/verify macos pr` completed but was not green. A clean detached
baseline reproduced these existing failures with the same test runner:

- `failedCrossDirectoryUpdateRemovesCopiedAttachmentsAndPreservesSource`
- `partialBatchRestoreUpdatesBothListsAndKeepsFailedNoteActionable` (both cases)
- `internalSaveEventDoesNotRebuildActiveSearchSession`
- `externalMarkdownOpensAndSavesInPlaceInLibraryWindow`

The first combined run also showed transient floating-window and uncached-tree
failures. Both passed the final focused run. Search presentation and rail-order
assertions introduced during this change were corrected and rechecked.

Final focused verification: 58 tests passed, covering search/core filters,
archive preference compatibility, cancellation, index reuse, snippets, search
entry, highlights, keyboard navigation, settings, rail navigation and uncached
note loading. The existing internal-save expectation above was explicitly
excluded only after it reproduced on the baseline. This is not a full-suite
pass claim.

Same-host debug benchmark, 1,500 synthetic notes (one sample per revision):

| Measurement | Baseline | Updated |
| --- | ---: | ---: |
| Cold session | 386.9 ms | 399.8 ms |
| Full single-term results | 22.3 ms | 18.7 ms |
| 40 warm queries | 129.4 ms | 85.6 ms |
| Mixed Latin/CJK query | unsupported | 12.1 ms |

These measurements describe the fixture, not a guarantee for every note library.
The cache schema changes only regenerable search data. The former combined
archive preference is retained until search and knowledge controls diverge;
compatibility tests cover both legacy choices.
