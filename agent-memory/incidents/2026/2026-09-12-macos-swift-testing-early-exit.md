# macOS Swift Testing exits before completing AppKit tests

Scope: macos verification only. Observed with Swift 6.3.3 / Testing 1902.

The generated SwiftPM async-main test host returned status 0 mid-suite, usually
near rich formatting / attachment paste or floating draft autosave. A zero exit
status did not establish a passing test run. Individual short filters could pass.

LLDB stopped on CFRunLoopStop scheduled from a run-loop block, followed by
libswift_Concurrency swift_task_asyncMainDrainQueue -> _swift_exit -> exit.
A persistent CFRunLoopSource did not prevent an explicit stop. Starting NSApp.run
inside a dispatched main-queue block blocked subsequent main-actor tasks; neither
attempt is retained. SwiftPM's custom entry-point flag did not replace its macOS
Swift Testing bundle host in this toolchain.

The verification script builds the existing tests, then loads that same bundle
in a synchronous AppKit host. Swift Testing owns reporting and final exit status;
AppKit owns the outer application event loop. No production AppController or
real NoteStore is launched. Unexpected event-loop return is a fatal failure.

Risk review: this changes only the macOS verification controller. It runs the
same tests and performance filters, inherits existing CI versus local performance
scope, uses synthetic fixtures, and does not package/install either platform.
All existing assertions remain gates. The PR must include both full completion
summaries and the separate Release performance summary. A controlled three-test
run already reported a real failure (rather than premature success), proving
that failed assertions propagate out of the host.

Diagnostics: /tmp/mudsnote-ccde-stop.log, /tmp/mudsnote-ccde-host-proof.log.

The completed full run reported 314 regular tests in five suites and eight
Release performance tests in two suites, all passing. The title-paste regression
was verified both by test and by reading the saved synthetic Markdown file.
Final completion evidence: /tmp/mudsnote-ccde-final-full.log (314 regular tests,
17.546 seconds; eight Release tests, 1.094 seconds; process exit 0).
