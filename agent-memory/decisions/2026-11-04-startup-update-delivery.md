# Startup update delivery boundary

The owner requested automatic version synchronization across Macs and checking
when opening Mudsnote. Scope is macOS; no iOS signing or installation changes.

Risk review: embed a small lifecycle bridge, not a second installer. Delegate to
the authenticated private Devflow recipient runtime and retain signature,
provenance, forward-update, rollback, journal, lock and running-app checks.
Do not quit an editor automatically. A detached helper waits for the installed
app to exit and then rechecks the service. It shares a watcher lock, closes its
standard streams, and expires after seven days. Reopening during installation
preparation must still defer through the existing installer.

Missing runtime and network/service failures are explicit states. UI test
fixtures and development/candidate bundles cannot initiate checks. The helper
uses system proxy settings because a GUI launch lacks shell environment setup.

Local live delivery may use the verified private recipient installation rather
than `verify macos live`, preserving Devflow provenance and its receipt. Run
the macOS PR gate, candidate and disposable installed-path smoke before private
publication; validate the installed application in a real window. Never claim
other recipients are installed without observing their receipts.
