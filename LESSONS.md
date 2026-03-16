# Lessons Learned

Append-only log of behavioral fixes and escalation history. One line per lesson.

- 2026-03: Supervised mode required 3 escalations in v1 (basic rules → self-check → "Violation = stop"). Next step is hook, not more instructions.
- 2026-03: DB audit lost ~30min on wrong infrastructure assumptions (confused timescaledb-prd with postgres-prd). Fix: Layer 2 context files loaded via walk-up.
- 2026-03: Context window exhausted during long analysis (EXPLAIN plans, index lists). Fix: write intermediate results to files, keep only summaries in conversation.
- 2026-03: Python/React conventions files contained ~80% defaults Claude already knows. Fix: keep only non-default choices (tooling, line length, framework).
