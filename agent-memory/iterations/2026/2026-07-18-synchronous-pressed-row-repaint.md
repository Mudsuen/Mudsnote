# Synchronous pressed-row foreground repaint

## Failure

The selected cell's title color changed during mouse-down, but AppKit's tracking loop deferred the visible repaint until release.

## Fix

After refreshing source cells during pointer deferral, call `sourceOutlineView.displayIfNeeded()` before returning to the tracking loop.

## Contract

The native highlight and yellow foreground both become visible on mouse-down; source navigation remains on mouse-up.
