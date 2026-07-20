# Mudsnote Agent Memory Start Here

## Fast Path

1. Read `AGENTS.md` and, for substantial work, `docs/AI_HANDOFF.md` once.
2. Run `./scripts/agent_context.sh --list`, then search one route with
   `./scripts/agent_context.sh <topic> '<regex>'`.
3. Consult `docs/ARCHITECTURE.md` only for boundary changes.
4. Search decisions/incidents only when current code does not answer the question;
   use iterations, archives, and global memory last.

Default context is `README.md`, `AGENTS.md`, this file, and—when needed—the
handoff. Roadmaps, changelog, refactor history, and old records are on demand.

## Routes

- Current constraints: `docs/AI_HANDOFF.md`
- Architecture: `docs/ARCHITECTURE.md`
- Source/tests: `scripts/agent_context.sh`
- Refactor history: `docs/REFACTOR_LOG.md`
- Decisions: `agent-memory/decisions/`
- Incidents: `agent-memory/incidents/YYYY/`
- Historical evidence: `agent-memory/iterations/`, then `agent-memory/archive/`
