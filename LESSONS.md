# Lessons Learned

Append-only log of behavioral fixes and escalation history. One line per lesson.

- 2026-03: Supervised mode required 3 escalations in v1 (basic rules → self-check → "Violation = stop"). Next step is hook, not more instructions.
- 2026-03: DB audit lost ~30min on wrong infrastructure assumptions (confused timescaledb-prd with postgres-prd). Fix: Layer 2 context files loaded via walk-up.
- 2026-03: Context window exhausted during long analysis (EXPLAIN plans, index lists). Fix: write intermediate results to files, keep only summaries in conversation.
- 2026-03: Python/React conventions files contained ~80% defaults Claude already knows. Fix: keep only non-default choices (tooling, line length, framework).
- 2026-06: While optimizing a query for perf, stated "1 CTE per source table" then immediately scanned the same 3.8GB table twice (emp+shr CTEs). Cause: ported the source's per-field structure instead of designing from the principle. Fix: explicit pre-output check — enumerate tables touched, none >1×, lead query with the table-list (memory feedback_one_pass_per_source_table).
- 2026-06: Repeatedly derived quantified "facts" (615 reported items, ~60/40 split, ~1h timing) from approximate/unverified methods (name-regex classification, single estimates) and masked the uncertainty with "roughly / it'll shift a bit". Several proved false once measured (advanced-superset, full-refresh ~3-4h not 1h). Fix: Honesty rule in CLAUDE.md — a number is a fact only from a direct measurement actually run; else label it an estimate + name the method; say "not measured" instead of approximating.
- 2026-06: Claimed `primary_company_id` "works for the 246" after hand-checking only 3 rows; an exhaustive predicate check then found 43/246 with no identity corroboration. Cause: answered a weaker structural question ("points to a head") and generalized a 3-row sample to the whole set. Fix: Honesty rule in CLAUDE.md — coverage claims ("holds for all N") require evaluating a checkable predicate on ALL N and enumerating failures, never sampling; state the exact predicate tested.
