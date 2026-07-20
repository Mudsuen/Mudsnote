# Design QA: iOS Notes-style grouped note list

## Evidence

- Source visual truth: `/Users/Donald/Downloads/IMG_5241.PNG`
- Final implementation screenshot: `/tmp/MudsnoteNotesListStyleFinalAttachments.II4pez/DE4DC3D3-C25A-4544-998B-E16A06657C71.png`
- Full-view side-by-side comparison: `/tmp/MudsnoteNotesListComparison.png`
- Viewport: source `1260x2736px`; implementation `1206x2622px`, normalized to the source size for comparison
- State: dark appearance; source is Apple Notes All iCloud, implementation is the Projects folder with two notes in the Today section
- Primary interactions tested: enter merged Inbox, open a folder, tap the full-width note row, enter editing, save, enter folder management, rename a folder, and exit management

## Findings

- P0: none
- P1: none
- P2: none after the second comparison pass
- Typography: the large navigation title, secondary note count, bold date section header, semibold row title, and muted timestamp/preview hierarchy match the native Notes reference closely.
- Spacing and layout rhythm: section headers align with the inset card edge; grouped rows share one rounded container and use inset separators; the bottom search and compose controls remain unobstructed.
- Colors and visual tokens: the implementation retains the project-native dark canvas and card tokens, which visually match the black Notes canvas and neutral dark grouped cards.
- Image and icon fidelity: no raster assets are needed in the list; all visible controls use native SF Symbols. Attachment state uses the system paperclip inline with metadata.
- Copy and content: fixture content differs from the personal reference by design. Folder location is intentionally absent because this screen is already scoped to Projects, as requested.

## Comparison History

### Pass 1

- Evidence: `/tmp/MudsnoteNotesListStyleAttachments.UkJ9cN/112A3F14-A286-4CD8-AC78-AE26F5320EC1.png`
- P2: attachment icons occupied a separate third line inside a folder, making rows taller than the Notes reference.
- P2: the Today header had an extra inset and did not align with the grouped card edge.
- Fix: moved the attachment indicator into the timestamp/preview line and set explicit section-header row insets.

### Pass 2

- Evidence: `/tmp/MudsnoteNotesListStyleFinalAttachments.II4pez/DE4DC3D3-C25A-4544-998B-E16A06657C71.png`
- Post-fix result: row density, section alignment, rounded grouping, separators, typography, and bottom controls have no remaining actionable P0/P1/P2 differences.

## Focused Region Comparison

- A separate crop was not needed because the original-resolution side-by-side comparison keeps row typography, separators, attachment symbols, card radii, and section alignment clearly readable.

## Follow-up Polish

- P3: content-dependent line lengths and the number of visible date groups will naturally vary from the personal Apple Notes library.

final result: passed
