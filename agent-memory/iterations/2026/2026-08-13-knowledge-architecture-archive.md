# Knowledge Architecture and Graph Archive

## Archive intent

- The installed macOS app was intentionally restored to the last commit before the hierarchical knowledge architecture.
- The knowledge work remains preserved in Git and can be resumed without reconstructing the design or implementation.
- This archive does not roll back, modify, build, install, or otherwise affect iOS.

## Restore boundary

- Pre-knowledge macOS commit: `e4b5121730defe285d3c6b319253b8ab91566427`
- First knowledge architecture commit: `d44e31ebf7f73ca54ed6ead1ff4b0c102f78eca6`
- Native knowledge graph commit: `cb7ca54fe581a1387eac523d789e8b1a5b57a15a`
- Last archived integrated implementation: `65de08aaeedc4d281d7b2da6975fc18571b439e4`

## Preserved implementation

### Hierarchical knowledge network

- Branch: `codex/20260813-20260813-knowledge-network`
- Pull request: `https://github.com/Mudsuen/Mudsnote/pull/87`
- Adds point, line, plane, and body knowledge layers.
- Classifies confirmed parent, child, and related Markdown or Wiki links separately from explainable suggestions.
- Adds relation navigation, local-first higher-layer synthesis, review-before-save behavior, and sandboxed Codex execution.
- Extends the Markdown search index with knowledge-layer and relationship metadata.

### Native visual knowledge graph

- Branch: `codex/20260813-20260813-knowledge-graph`
- Pull request: `https://github.com/Mudsuen/Mudsnote/pull/88`
- Adds a read-only native macOS graph with focused one-to-three-hop and connected global scopes.
- Preserves stable layer lanes and shapes, layer filters, title search, pan, zoom, fit-to-window, and same-library node navigation.
- Builds graph edges only from confirmed Markdown or Wiki relationships; suggestions remain visually and structurally separate.

### Follow-up launch corrections

- Pull request: `https://github.com/Mudsuen/Mudsnote/pull/94`
- Commit: `65de08aaeedc4d281d7b2da6975fc18571b439e4`
- Defers knowledge indexing until the first macOS note is visible.
- Canonicalizes nested knowledge roots so relation queries reuse the parent library index.

## Resume procedure

1. Start from the archived feature branches or cherry-pick `d44e31e` followed by `cb7ca54`.
2. Include the launch corrections from `65de08a` before testing against an iCloud-backed library.
3. Run `./scripts/verify macos pr`.
4. Install only after explicit macOS approval with the Devflow candidate-install path.

## Data boundary

- The knowledge implementation is local-first and keeps Markdown files canonical.
- Restoring the older app does not delete or rewrite user notes.
- Any knowledge metadata already written inside Markdown remains ordinary Markdown content and is not removed by the app rollback.
