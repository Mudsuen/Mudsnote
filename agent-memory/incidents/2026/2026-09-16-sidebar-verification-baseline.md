# macOS sidebar verification baseline — 2026-09-16

Scope: macOS sidebar polish on main, based on f1a6bbf.

The macOS PR verification log reported failures outside sidebar styling. A clean
`git archive HEAD` copy at `/tmp/mudsnote-sidebar-baseline` reproduced failures in:

- libraryGalleryModeCollapsesListAndPreservesSelection
- libraryToolbarUsesNotesLikeDisabledStates
- libraryWindowEditorToolbarInsertsRichMarkdownTools
- libraryAndFloatingEditorsManageMarkdownLinks
- localMarkdownCommandClickOpensInsideLibraryAndShowsLinkRelations
- libraryNoteListShowsImageAttachmentThumbnail

The first five produced 11 issues; the thumbnail test produced one issue.
These are baseline failures and were not changed as part of sidebar styling.
The complete PR run ended without a test-suite summary, so its exit status alone
must not be represented as a passing full suite.

Local logs: `/tmp/mudsnote-sidebar-verify.log`,
`/tmp/mudsnote-sidebar-baseline.log`, and
`/tmp/mudsnote-sidebar-baseline-thumbnail.log`.

Before the local install, the existing app was retained at
`/tmp/Mudsnote-before-sidebar-20260916.app`. To recover the binary, quit Mudsnote,
restore that bundle to `/Applications/Mudsnote.app`, then launch it. This does
not roll back notes or settings.

Final focused verification passed all four tests: libraryWindowUsesNotesLikeSplitAndLoadsFirstNote,
librarySplitLayoutPersistsAcrossWindows, libraryPinnedNotesGroupAndMenusMatchSelectionState,
and libraryNoteScrollViewFitsSingleColumnToVisibleWidth. The last test uses a
legacy vertical scroller to catch clipped selection backgrounds and column widths.
