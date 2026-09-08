# Xcode account loss and signing refresh failure

## Evidence

- 2026-09-08 05:27 local system log: DVTDeveloperAccountCredentialsError,
  missing Xcode-Username. No credential values were collected.
- Xcode Apple Accounts UI and its account-list preference were empty.
- The default user keychain search list included login.keychain-db. A targeted
  metadata lookup for the logged account identifier found no matching item.
  This does not establish who removed it or whether it exists in another store.
- Active Surge profile retained DIRECT rules for Apple authentication domains.
- Scheduled renewal selected the Any iOS Device placeholder as a concrete ID.
  Every failure notification incorrectly requested reauthentication.

## Changes and risk review

- Exclude placeholder and ineligible destinations; retain generic iOS fallback.
- Request sign-in only for classified authentication failures.
- Pause auto-install checks after authentication failure until manual --run.
  This deliberately leaves renewal paused even after sign-in until that retry.
- No keychain deletion, preference reset, credential storage, network change,
  device registration, or app installation. Existing profile restoration remains.
- Apple forum thread 765741 documents the same error and an account-list reset
  workaround, not a durable fix. Resetting an already empty list has no benefit.
  Account-loss causality remains unproven; reauthentication is still required.

## Verification

- scripts/test_ios_signing_refresh.sh passed with synthetic destination,
  notification, and authentication retry fixtures.
- scripts/verify ios pr passed, including simulator build-for-testing.
- Live manual --run used generic/platform=iOS, failed with No Accounts, restored
  cached profiles, and recorded xcode-account-authentication.
- Subsequent --run --auto-install skipped renewal after authentication failure.
- No live installation was attempted. After the user signs in, run manual
  --run and verify account persistence and renewed profiles before installation.
