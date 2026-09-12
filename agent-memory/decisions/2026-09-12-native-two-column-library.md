# Native two-column library

Scope: explicitly both macOS and iOS, requested 2026-09-12.

The user requested a substantial reduction in interface chrome, native translucent materials, two columns, and intelligent bidirectional links instead of knowledge hierarchy.

## Design basis

The installed Mac app exposed a source column, list, persistent editing toolbar, and a knowledge-relations footer with layer and graph actions. The existing iOS list also placed individual notes in glass containers.

Apple's material guidance separates navigation/control materials from content:
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

The implementation uses AppKit sidebar/content materials, a transient folder popover, and SwiftUI native sheets and split navigation. Main content stays visually quieter than navigation. Folder and note lists retain descriptive accessibility labels even when their entry point is an icon.

## Compatibility and risk review

No user notes, folders, tags, credentials, or metadata are migrated or deleted. Existing knowledge metadata remains parsable for old notes. Active library and mention suggestions use directional links without layer categorization. The existing filesystem/index and save paths remain owners; iOS backlink targets are metadata in the existing paged index.

This is an unfinished UI checkpoint on `codex/native-two-column`; no Draft PR or installation has been completed. The installed app must retain a recoverable receipt before any replacement. The project delivery rule requires an integrated, verified main candidate for installation; branch preview uses isolated synthetic notes. The physical iPhone was unavailable to CoreDevice during verification, so device installation requires reconnection plus signing/recovery validation.

Keyboard entry points on Mac: Command-N new note, Command-F search, Control-Command-S folders, Shift-Command-P quick menu, Shift-Command-L links, Shift-Command-M source; existing editor formatting, slash, and @ commands remain available.

## Platform follow-up requested by the user

The user requested separate Mac and iOS conversations. The Mac appearance is not accepted: redesign the layout with a slightly darker list and brighter content, a clear visual hierarchy, and smooth native transitions that respect Reduce Motion. iOS should focus on visual refinement and a functional review. Preserve the two-column / folder-picker / intelligent-link intent while reviewing the implementation instead of assuming the checkpoint is final.

Verification so far: iOS `verify ios pr` passed eight focused UI cases on the latest code; a preceding full run also passed unit tests and Release build. The iPad-only case skipped, so regular-width behavior remains unverified. Mac real-window preview and five focused link tests passed, but broad Swift runs ended without a complete suite summary, and one release performance case failed while another build was running. Mac requires fresh complete verification after refinement. Do not present this checkpoint as delivery-ready.
