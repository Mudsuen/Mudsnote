# Sidebar navigation cost

Rail navigation should switch the browser without replacing an unchanged editor.
Directory and Tags reuse `sourceDirectoryRootItems`; tree filtering records its
projection scope so switching out of Recent/Favorites still restores all notes.
Snapshot, folder, tag, and pin mutations keep their existing rebuild paths.

The default sidebar has one heading. The redundant scope/count/presentation row
was removed. Search scope remains available while searching, and a selected tag
or folder can use the primary heading.

Cached navigation benchmark: 80 synthetic notes in eight folders with eight
tags, debug build, median of three transitions including layout.

| Destination | Before | After |
| --- | ---: | ---: |
| Directory | 76.5 ms | 20.4 ms |
| Tags | 44.1 ms | 11.0 ms |
| Recent | 30.0 ms | 11.9 ms |

`sidebarNavigationKeepsCachedContentResponsive` also checks that active-document
selection survives browsing, repeated clicks do not add history, interrupted
loads recover, gallery data refreshes, and leaving Trash loads an editable
ordinary note. Initial indexing is outside this cached-navigation benchmark.

Faster navigation exposed an already queued overview viewport reset. Ignore
that reset while a card transition is active so a quick click keeps its anchor.
