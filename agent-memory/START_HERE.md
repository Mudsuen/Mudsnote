# Mudsnote Agent Memory Start Here

## Fast Path

Use the context command in `AGENTS.md`; do not restart the routing chain here.
Search decisions/incidents only when the routed context and current code do not
answer the question. Handoff, roadmaps, changelog and old records are on demand.
Exclude archives unless explicitly requested.

## Routes

- Current constraints: `docs/AI_HANDOFF.md`
- Architecture: `docs/ARCHITECTURE.md`
- Source/tests: `scripts/agent_context.sh`
- Refactor history: `docs/REFACTOR_LOG.md`
- Decisions: `agent-memory/decisions/`
- Incidents: `agent-memory/incidents/YYYY/`
- Historical evidence: `agent-memory/iterations/`, then `agent-memory/archive/`
