# Mudsnote Agent Memory Start Here

## Fast Path

1. Read `AGENTS.md`; in a Devflow worktree, obtain `./scripts/agent_context.sh --task`.
2. Search one route with
   `./scripts/agent_context.sh <topic> '<regex>'`.
3. Consult `docs/AI_HANDOFF.md` or `docs/ARCHITECTURE.md` only when current constraints or boundary changes require them.
4. Search decisions/incidents only when the capsule and current code do not answer the question;
   use iterations, archives, and global memory last.

Default context is the task capsule plus the routed source/test set. This file,
handoff, roadmaps, changelog, refactor history, and old records are on demand.

## Routes

- Current constraints: `docs/AI_HANDOFF.md`
- Architecture: `docs/ARCHITECTURE.md`
- Source/tests: `scripts/agent_context.sh`
- Refactor history: `docs/REFACTOR_LOG.md`
- Decisions: `agent-memory/decisions/`
- Incidents: `agent-memory/incidents/YYYY/`
- Historical evidence: `agent-memory/iterations/`, then `agent-memory/archive/`
