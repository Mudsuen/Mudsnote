# Overview inline editor undo routing

- Trigger: insert text through `MarkdownTextView.insertText` while the shared
  editor is embedded in an overview card.
- Evidence: the regression check raised `NSInternalInconsistencyException`:
  `NSUndoManager ... is in invalid state, must begin a group before registering undo`.
- Cause: the editor inherited `LibraryOverviewView.structuralUndo`, whose
  `groupsByEvent` is false because canvas mutations group their own changes.
- Repair: use the normal responder-chain undo manager while a note or topic
  editor is active; retain the structural manager for canvas commands. Finish
  the embedded editor's new layout and reveal its selection before focusing it.
- Verification: the inline-creation check now inserts a title and body through
  the text-input API, confirms a visible insertion point and dirty state, then
  collapses the card and reads the saved body. The scoped macOS UI suite passes.
