# 2026-07-13 native toolbar interaction

## Goal

Align compact macOS toolbar button material and interaction with Apple Notes while preserving the approved small window and toolbar geometry.

## Changes

- Kept the editor-tools group at `155x32pt` with five `31pt` command tracks.
- Used public AppKit `NSGlassEffectView` for the group and `.toolbar` `NSButton` controls with `showsBorderOnlyWhileMouseInside` for native hover and pressed drawing.
- Replaced static glass wrappers around New Note and the collapsed Sidebar Toggle with native macOS 26 `.glass` buttons.
- Gave expanded Add Folder and Sidebar Toggle the same system hover-only toolbar behavior.

## Evidence

- Full tests, installed-app library smoke, packaging, and strict signature validation passed.
- Packaged content comparison: `/tmp/mudsnote-visual-qa-199-native-hover/apple-notes-vs-mudsnote.png`.
- Real-pointer frames: `/tmp/mudsnote-native-button-hover.png` and `/tmp/mudsnote-native-button-rest.png`; the image bytes differ after hovering `Aa`.

## Decision

Do not replace the compact group with `NSToolbarItemGroup`: its public automatic representation uses roughly `44pt` segments and expands the five-command group well beyond the measured Notes width. Public `NSGlassEffectView` plus native toolbar buttons keeps AppKit-owned interaction without giving up the reference geometry.
