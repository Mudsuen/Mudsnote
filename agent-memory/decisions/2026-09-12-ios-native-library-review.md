# iOS native library and reader review

Scope: iPhone (`ios`). Preserve existing Markdown files, folders, tags, and
explicit view preferences. The device-family setting remains iPhone-only.

Use the native folder sheet for choosing and managing folders. Open its
secondary pages on the home navigation stack after dismissal; presenting a
root reader while that sheet owns a pushed tag page competes for presentation.
Keep the quick note composer and file permission importer on the root.

The reader remains large and shows a small native action menu plus Close.
Expose Previous Note for linked navigation and reload its file on return,
rather than trusting a body snapshot captured before editing. Derive link
metadata from Foundation Markdown parsing, preserving the existing relative
path validation and library indexing boundaries.

The old drawer implementation and unverified regular-width split view are
removed. No new iPad device-family support, data migration, signing change, or
macOS install belongs to this task. See `docs/ios-visual-functional-review.md`
for the completed verification record.
