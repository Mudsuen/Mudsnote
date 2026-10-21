# Personal Mac updates

Scope: macOS only. This mechanism updates Mudsnote's executable, not Markdown
notes or settings. Existing note storage, including a user-selected iCloud
folder, remains independent.

## Enable on each Mac

Requirements: macOS 26+, full Xcode with Swift 6.3+, Git access to this repository,
a writable `/Applications`, and Python 3 (included with Xcode's tools). Each
Mac builds its native architecture. Accept Xcode's license and finish its setup
interactively before enabling updates.

From an existing Mudsnote checkout:

```sh
python3 scripts/macos_update.py install-agent
```

Without a checkout, clone this repository and run the same command:

```sh
git clone https://github.com/Mudsuen/Mudsnote.git Mudsnote
cd Mudsnote
python3 scripts/macos_update.py install-agent
```

The per-user LaunchAgent checks every 15 minutes and at login. Quit Mudsnote to
allow an update. Checks, tests and installation are deferred while the app is
running. Builds can take several minutes. No Xcode, Git credentials or signing
identities are installed or changed by the updater. Missing prerequisites or
locked signing keys stop that attempt, preserving the installed app.

The stable bootstrap, isolated source checkout, logs and backups live under
`~/Library/Application Support/Mudsnote/Updates`. Development checkouts are
never pulled, reset or cleaned. The source checkout only follows `origin/main`
from the fixed repository URL; edits and rewritten/non-descendant history stop
updates. A normal `git revert` remains eligible because it is a new descendant.

## Verify and recover

```sh
python3 scripts/macos_update.py status
python3 scripts/macos_update.py run
python3 scripts/macos_update.py uninstall-agent
python3 scripts/macos_update.py rollback
```

`status` reports the installed commit and backup receipt. `run` checks now.
Disable the agent and quit the app before rollback, so the next poll cannot
immediately reinstall the newer commit. Rollback keeps another backup and does
not alter user notes or settings. Backups are retained for explicit cleanup.

## Delivery and risk review

- `verify macos pr` runs synthetic updater fault tests and macOS app tests.
- `package_app.sh --candidate-only` builds and signs `dist/Mudsnote.app`, verifies
  it, and embeds `MudsnoteSourceRevision`; it does not touch the installed app.
- The installer validates the bundle ID, executable and signature, stages on
  the application volume, journals the swap, preserves the previous app, and
  restores it if validation fails. An interrupted swap is recovered next run.
- Normal local `verify macos live` builds the candidate, requests a graceful app
  quit, installs it with a receipt, and launches it. A cancelled quit never
  becomes a forced kill. No note directories or settings are deleted.
- Automated updates never quit or launch the app. A launch detected before the
  swap defers installation. A very small launch-versus-rename race remains;
  launching during an update may run the previous executable until next launch.
- The bootstrap is refreshed from a verified commit after successful automatic
  installation. Distribution trusts the owner's GitHub `main` branch and local
  code-signing tools; this is a personal source-based updater, not a notarized
  consumer release channel.

For distribution to Macs without Xcode, migrate to signed, notarized release
archives and a signed Sparkle feed. That requires a separate release/signing
setup; it is not needed for the current personal Mac development workflow.
