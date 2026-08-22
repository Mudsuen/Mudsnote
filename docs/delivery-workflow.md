# Mudsnote Delivery Exceptions

The shared default is `/Users/Donald/Code/AGENTS.md`. This document contains
only Mudsnote-specific verification and safety requirements.

## Platform scope

- Every runtime task declares `macos`, `ios`, or explicit `both`.
- Use `./scripts/verify <scope> pr|full|live`.
- `both` is valid only for an explicitly dual-platform request.
- `live` never infers a platform. iOS-only work must not package or install
  macOS, and macOS-only work must not use the connected iPhone.
- Documentation-only work runs policy checks without building either app.

## CI and installation boundaries

- CI must use synthetic data and must not access iCloud, Keychain, real note
  folders, personal settings, credentials, a connected device, or installed
  applications.
- Worktrees share `/Applications/Mudsnote.app` and the connected iPhone, so
  live verification is serialized and explicit.
- Install a reversible candidate only when the user needs local experience.
  The candidate comes from verified local `main` and retains its restore
  receipt.

## Independent gates

Migration, irreversible data, production/App Store release, signing, secrets,
entitlements, permissions, packaging, and verification-controller changes
require an explicit risk review; use a PR/CI gate when the project or user
requires it. Git rollback cannot claim to reverse an external side effect.
