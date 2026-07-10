# List Scroll I/O

## Scope

- Baseline: `1925955 Restore unified Notes titlebar`
- Preserve note ordering, snippets, tags, attachment indicators, thumbnails, and cell reuse behavior.
- Remove repeated image decoding while scrolling and repeated Markdown reads when resolving recent notes.

## Findings

- Note and group cells already used `NSTableView.makeView`, so view reuse was not the bottleneck.
- Every note-cell configuration still called `fileExists` and `NSImage(contentsOf:)` for its thumbnail.
- Recent-note resolution could synchronously reopen up to 80 Markdown files to hydrate metadata already present in the search-index snapshot.

## Implementation

- Added positive and negative thumbnail caching keyed by standardized attachment path.
- Decode thumbnails through ImageIO at a maximum of `88px`, matching the `44pt` Retina slot instead of retaining arbitrary full-size images.
- Build recent-note results by joining recent paths against the indexed all-note snapshot, with lightweight metadata fallback for paths absent from the snapshot.

## Verification

- Targeted main-layout and image-thumbnail tests passed.
- The thumbnail test configures the same note cell twice and confirms the decode counter remains `1`.
- Full `swift test` passed: 103 tests in 2 suites.
- Production build emitted no warnings.
- `git diff --check` passed.
- `./scripts/package_app.sh` installed the build at `/Applications/Mudsnote.app`.
