# Mudsnote Delivery Exceptions

The shared lifecycle is
`/Users/Donald/Code/Devflow/docs/workspace-delivery-policy.md`. This document
contains only Mudsnote-specific exceptions.

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
require the shared PR/CI gate. Git rollback cannot claim to reverse an external
side effect.
