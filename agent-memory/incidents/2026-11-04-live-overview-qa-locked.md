# Native overview QA blocked by the Mac lock screen

The live Mubu reference was inspected in a disposable neutral document, including
five nesting levels, outline indentation, drill-down, subtree drag/delete,
undo/redo, descriptions, appearance modes, map palette and zoom.

The first attempt to inspect the new native preview returned: "The Mac is locked
and automatic unlock could not unlock it." The owner was asked to unlock the Mac
manually. Do not work around the lock screen or change authentication settings.

Pending gate after unlock:
1. Restart the latest isolated preview under `/tmp/mudsnote-live-reference-20261104`.
2. Compare the map and outline against the live neutral reference in both
   appearances, matching the content viewport and depth. Check long labels,
   descriptions, hover gutters, root centering and zoom/structure/palette controls.
3. Exercise native selection/editing, focus breadcrumbs, five-level folding,
   bullet drag, invalid cyclic drops, deletion/undo, and linked-note editor saves.
4. Move the temporary Mubu document to its normal recoverable Trash and return
   the user's tab to its original document. The original app appearance preference
   was already restored to Follow System during reference inspection. Temporary
   source-session pointers are kept outside Git in the disposable fixture folder.
5. Only after visual QA passes, verify a clean candidate, integrate/push main and
   install the macOS app. iOS remains outside scope.

The installed app remains at the previously verified main revision until this
native gate is completed. The full PR test limitations from the preceding work
remain documented in `2026-11-03-overview-verification-baseline.md`; this follow-up
uses affected overview/library checks rather than repeating the known blockers.

## Integration follow-up

Remote `524302f` was merged without dropping either font resources or the packaged
update-check helper. Its ordinary-navigation and sidebar fixes are retained.
A full merged macOS PR run executes 406 Swift tests and 18 Python tests. Python
passes; the remaining Swift failure expects a floating browser window to become
the key window. It reproduces on unchanged `524302f` on this locked MBP. Keep the
assertion and rerun after unlock. A separate hidden-search TagInput focus failure
also reproduced on the baseline; its test setup now uses a shown window and the
actual Search entry and passes in the merged suite.

The coordinating Mac mini chat owns final installation/private publication. This
chat must not publish Devflow bundles or modify the Mini's installed app. Do not
push main until the pending native gates pass.

Static combined-candidate acceptance passes: deep/strict signature, team
`3JA29GL46S`, installed designated requirement continuity, exact font/license and
update-helper bytes, helper Python syntax, and actual bundled font loading through
CoreText. This does not replace native window acceptance. The current snapshot
and candidate path are in `/tmp/mudsnote-live-candidate-verification.json`; no
installed app or private release was modified.
