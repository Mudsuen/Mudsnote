# 2026-05-08 simplify heading toolbar highlight

## Request

- Do not put H1, H2, and H3 all in the floating note toolbar.
- Make toolbar highlight feedback a little lighter.

## Baseline

- Branch: main
- HEAD: 7df72ae
- Dirty files before work: none.

## Changes

- Reduced the toolbar to one `H` heading button, which applies Heading 1.
- Kept Heading 2 and Heading 3 available through `cmd+option+2`, `cmd+option+3`, and slash commands.
- Lowered hover and active toolbar highlight alpha values so the white fill reads more quietly.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.
