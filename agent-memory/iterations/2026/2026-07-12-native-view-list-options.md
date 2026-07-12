# Native View-menu list options

## Decision

- Keep the toolbar free of the user-rejected ellipsis control.
- Expose Edit Date, Creation Date, and Title sorting under View > Sort By.
- Expose Group By Date as a checked View-menu command.
- Route commands through `AppController` to the current library controller.
- Use `NSMenuItemValidation` so checkmarks reflect live window state or persisted defaults.

## Boundary

- The existing list-options menu builder remains useful for context and unit coverage, but no toolbar entry is required.
- Full-suite verification exposed and fixed a trash-snapshot integration gap: deleting a folder must remap all contained note URLs into the returned trashed-folder URL before rebuilding source counts.
