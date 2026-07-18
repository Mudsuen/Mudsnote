# Immediate pointer visuals with release navigation

## Contract

- Mouse-down moves the native source-row highlight immediately.
- Yellow title, icon, and selected count styling move with that highlight immediately.
- Mouse-up commits logical scope, save, and note-list navigation.

## Boundary

Do not delay or custom-own the row background. During pointer deferral, cell colors follow `selectedRowIndexes`, while `selectedScope` remains unchanged until release.
