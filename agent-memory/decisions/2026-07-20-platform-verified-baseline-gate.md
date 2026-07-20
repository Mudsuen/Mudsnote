# Platform verified baseline gate

Status: superseded on 2026-07-20 by Devflow V2.

The short-lived design stored separate moving macOS/iOS accepted commit markers and blocked overlapping PR paths. The full workflow review found that this preserved the original source of friction: accepted work could still remain outside `main`, while every task gained another marker and overlap decision.

Current decision:

- latest `origin/main` is the only daily integration baseline;
- reversible tasks use Ready PRs and event-driven merge after current merge-candidate CI;
- legacy PRs remain manual instead of being treated as an implicit baseline;
- important changes are highlighted after completion, while irreversible data, production/signing, guardrail weakening, and control-plane changes keep an independent hold;
- code rollback uses a verified Revert PR.
