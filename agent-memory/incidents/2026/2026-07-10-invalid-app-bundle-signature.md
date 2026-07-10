# 2026-07-10 invalid app bundle signature

## Failure

`./scripts/package_app.sh` produced a launchable `/Applications/Mudsnote.app`, but strict verification failed with `code has no resources but signature indicates they must be present`.

## Cause

The script copied a built executable and resources into a new app bundle without signing the final bundle.

## Recovery

- Clear extended attributes after assembly.
- Select the first available Apple Development identity by certificate hash, not display name.
- Fall back to ad-hoc signing when no development identity is available.
- Sign the complete app bundle before LaunchServices registration and launch.

## Verification

`codesign --verify --deep --strict --verbose=2 /Applications/Mudsnote.app` passed and the installed app remained running.
