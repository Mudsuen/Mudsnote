# AppKit verification and live-window automation

During a delivery rerun with live preview automation interleaved, the existing
floatingWindowManagerBoundsSearchCandidates test returned zero results instead
of 100. The preceding full runs passed. Rerunning with computer interaction
paused passed all 321 ordinary tests without changing or weakening that test.
Window-focus interference is a plausible cause, not a proven diagnosis. Keep
real-window interaction and the AppKit host test run sequential during delivery.
