---
description: "PostgreSQL patterns: indexing, query optimization, EXPLAIN analysis, constraints, partitioning. Auto-activates for PostgreSQL codebases."
---

# PostgreSQL Patterns

## EXPLAIN Analysis

- Always use `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` — not just `EXPLAIN`. Without ANALYZE you get estimates, not actuals.
- Read plans bottom-up: innermost nodes execute first.
- Key warning signs in plans:
  - `Seq Scan` on large tables with a WHERE clause → missing index
  - `Nested Loop` with high row counts on both sides → consider Hash Join via index or restructure
  - `Sort` with `external merge Disk` → `work_mem` too low or sort avoidable
  - `Rows Removed by Filter` >> `Actual Rows` → index not selective enough
- After schema changes, run `ANALYZE` on affected tables before interpreting EXPLAIN output.

## Indexing

- Create indexes to support query WHERE clauses and JOIN conditions, not speculatively.
- Composite indexes: column order matters. Put equality conditions first, range conditions last.
- Use `INCLUDE` columns to create covering indexes when you need to avoid heap fetches.
- Partial indexes (`WHERE condition`) for queries that always filter on the same predicate.
- Never index columns with very low cardinality (booleans, status enums with 2-3 values) unless combined with selective columns.
- `CONCURRENTLY` for index creation on production tables — blocks writes otherwise.

## Constraints

- Use `NOT NULL` by default. Only allow NULL when absence of value has business meaning.
- Foreign keys: always create an index on the referencing column (PostgreSQL does NOT auto-index FK columns).
- `CHECK` constraints for domain validation (positive amounts, valid ranges). Cheaper than application-level checks.
- Use `EXCLUDE` constraints for range overlap prevention (e.g., date ranges that must not overlap).

## Query Patterns

- Use CTEs (`WITH`) for readability, not performance. PostgreSQL 12+ inlines CTEs by default, but `MATERIALIZED` forces a barrier if needed.
- Prefer `EXISTS` over `IN` for subqueries that return many rows.
- `DISTINCT ON (col) ... ORDER BY col, other_col` is a PostgreSQL-specific pattern for "first row per group" — faster than window functions for simple cases.
- Never use `SELECT *` in application queries. Explicit column lists prevent breakage on schema changes and allow covering indexes.
- Use `FOR UPDATE SKIP LOCKED` for job queue patterns — avoids blocking.

## Migrations

- Every migration must be reversible. Include both `up` and `down`.
- Add columns as `NULL` first, backfill, then add `NOT NULL` constraint. Adding `NOT NULL` with a default locks the table on older PostgreSQL versions.
- Rename columns in two steps across deployments: add new → migrate reads → drop old. Never rename in one step with live traffic.
- Large table alterations: use `pg_repack` or create-swap pattern instead of `ALTER TABLE` which locks.

## Anti-Patterns

- NEVER use `OFFSET` for deep pagination. Use keyset pagination (`WHERE id > last_seen_id ORDER BY id LIMIT n`).
- NEVER store JSON in PostgreSQL when the data has a known, stable schema. Use proper columns.
- NEVER use `text` type for columns that have a bounded domain. Use `varchar(n)` or domain types.
- NEVER concatenate SQL strings. Use parameterized queries exclusively.
