# AppKit-owned mouse-up commit

## Failure

`NSOutlineView.mouseDown` tracks the primary click through release before returning. A separate `mouseUp` override therefore never finished the source-selection deferral, leaving real pointer navigation inert.

## Fix

- Begin source-selection deferral before calling `super.mouseDown`.
- Finish and commit immediately after `super.mouseDown` returns.
- Keep keyboard selection outside this pointer-only deferral.

## Verification boundary

The installed app must be clicked through Computer Use after packaging. A unit test that only calls the begin/finish helpers is insufficient evidence for the real AppKit event path.
