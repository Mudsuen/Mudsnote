# Private Mac application updates

Scope: macOS application bundles only. Markdown notes, iCloud synchronization,
settings, and iOS distribution are independent.

## Normal behavior

The installed `/Applications/Mudsnote.app` checks the private published bundle
after launch without blocking its window. Dock reopen also checks, throttled to
once per 15 minutes. **Mudsnote → Check for Updates** checks immediately and
shows the result. The same menu shows the exact installed source revision, so
two builds with the same marketing version can be distinguished.

An available update is installed after Mudsnote exits. The helper waits in the
background, never quits the app, and the existing updater checks again before
replacement in case the app reopened. Successful installation takes effect on
the next launch. Failed checks and rolled-back releases never display “latest”.
The private recipient service still performs its scheduled checks when the app
is not opened. A waiting helper expires after seven days; a later launch/check
can start a new watcher.

## Service prerequisite and delivery

Each Mac needs the authenticated private Devflow recipient bootstrap. Mudsnote
uses `~/Library/Application Support/DevflowUpdates/runtime/app_updates.py` and
its adjacent `apps.json`. A missing service is reported in the menu; the app
does not install credentials, clone source, or compile on recipient Macs.
The bridge honors system HTTP/HTTPS proxy settings for GUI launches.

Builds and tests run on Mac mini; verified archives are published through the
Devflow private delivery service. A commit or a laptop-local build is not a
published update. The owning setup, signing and rollback instructions are
`Devflow/updates/README.md` in the shared Code workspace.

The app bridge only requests the Mudsnote recipient adapter. All signature,
hash, source provenance, forward-update, rollback and installation journal
checks stay in that service. It does not bypass failure backoff. Fixture/test
launches and bundles outside `/Applications/Mudsnote.app` never check updates.

The older `scripts/macos_update.py` remains the local candidate installer with
its recovery receipt; its source-building LaunchAgent is superseded. Do not
enable that legacy agent on recipient Macs.
