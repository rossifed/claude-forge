---
name: db-index-drift
description: "Detect drift between code-defined indexes (raw_indexes Dagster assets, SQLAlchemy models) and actual database state (pg_indexes). Compares raw and master schemas, finds duplicates, name mismatches, missing indexes, and naming anomalies."
user-invocable: true
argument-hint: "[env:test|prod] [scope:raw|master|all]"
---

# DB Index Drift

Compare index definitions in code (source of truth) against actual database state. Detect divergences that accumulate from manual changes, renamed assets, or migrations without explicit names.

## Parameters

| Param | Values | Default |
|---|---|---|
| `env` | `test` → `mcp__pg-financial-hetzner-test__execute_sql`, `prod` → `mcp__pg-financial-aws-prod__execute_sql` | `test` |
| `scope` | `raw` (raw schema only), `master` (master schema only), `all` (both) | `all` |

## Workflow

### Step 1: Collect DB state

Run these queries on the target environment MCP server.

**Raw indexes:**
```sql
SELECT indexname, tablename, indexdef
FROM pg_indexes
WHERE schemaname = 'raw'
ORDER BY tablename, indexname;
```

**Master indexes (non-history only):**
```sql
SELECT indexname, tablename, indexdef
FROM pg_indexes
WHERE schemaname = 'master'
  AND tablename NOT LIKE '%_history'
ORDER BY tablename, indexname;
```

Save results to working variables — do NOT write intermediate files.

### Step 2: Collect code definitions

**Raw indexes** — read all files in:
```
src/data/data/etl/master/assets/infrastructure/raw_indexes/*.py
```
Extract from each asset function: index name, table name, columns, whether functional (contains `::` cast), whether partial (contains `WHERE`).

**Master indexes** — read all SQLAlchemy model files in:
```
src/data/data/db/models/*.py
```
Extract from `__table_args__` tuples: `Index(...)`, `PrimaryKeyConstraint(...)`, `UniqueConstraint(...)` definitions. Map each to: index name, table name (`__tablename__`), columns, type (pk/unique/index).

### Step 3: Compare and classify

For each scope, classify every divergence into exactly one category:

| Category | Definition | Priority |
|---|---|---|
| **DUPLICATE** | Two DB indexes on same table with identical columns | P1 — drop one |
| **MISSING_IN_DB** | Code defines index, DB doesn't have it (exact name match fails AND no column-equivalent exists) | P2 — create |
| **MISSING_IN_CODE** | DB has index, no code definition matches by name or columns | P2 — add to code or drop |
| **NAME_MISMATCH** | DB and code define same columns on same table but under different names | P3 — rename |
| **FUNCTIONAL_MISMATCH** | One side has `column::type` cast, other has raw column | P3 — replace |
| **HASH_NAMED** | Master index with hex hash name (Alembic auto-generated, pattern: `^[0-9a-f]{32}$`) | P4 — cosmetic rename |
| **PK_NAME_MISMATCH** | DB has auto-generated PK name (e.g., `tablename_pkey`) vs code's explicit name (e.g., `pk_tablename`) | P4 — cosmetic |

**Matching algorithm:**
1. First pass: exact name match between DB and code → ALIGNED (skip)
2. Second pass: for unmatched, compare columns (normalize order, strip casts for comparison) → NAME_MISMATCH or FUNCTIONAL_MISMATCH
3. Remaining unmatched DB indexes → MISSING_IN_CODE
4. Remaining unmatched code indexes → MISSING_IN_DB
5. Scan all DB indexes per table for column duplicates → DUPLICATE
6. Scan master DB indexes for hash pattern → HASH_NAMED

**Exclusions (do not flag):**
- `_history` table indexes (`master_*_history_sys_period_idx`) — managed by temporal_tables extension
- DLT auto-generated indexes (`*__dlt_id_key`) — managed by DLT framework
- Tables that exist in DB but have no SQLAlchemy model (derived/materialized tables managed by DBT or Dagster assets) — these are expected

### Step 4: Generate report

Format as markdown with sections per scope and category. Include:

**Header:**
```markdown
# Schema Drift Report
**Date:** YYYY-MM-DD | **Environment:** test/prod | **Scope:** raw/master/all
```

**Summary table:**
```markdown
| Scope | DB Count | Code Count | Duplicates | Missing DB | Missing Code | Name Mismatch | Hash Named |
```

**Detail sections** — one per category with non-zero findings. Each entry shows: table, DB index name, code index name, columns, recommended action.

**Recommended actions** — at the end, grouped by priority, with executable SQL for P1 (DROP duplicates) and P2 (CREATE missing).

### Step 5: Present report

Display the full report directly in the chat. Then ask the user if they want to save it somewhere. Do NOT save automatically — the report is a diagnostic, not a project artifact.

If the user wants to save:
- Let them choose the location (e.g., `~/Documents/data/schema-drift/`, a project path, or anywhere else)
- Suggest filename: `YYYY-MM-DD_<scope>_<env>.md`

## Edge Cases

- **Prod MCP requires SSH tunnel on port 5434.** If the prod query fails, remind the user to open the tunnel.
- **Tables not yet ingested.** If code defines indexes on tables that don't exist in DB (e.g., new Sling streams not yet run), note them separately as "pending first ingestion" rather than MISSING_IN_DB.
- **Partial indexes.** Compare the WHERE clause too — same columns with different WHERE is a distinct index, not a duplicate.
- **Column order matters for btree.** `(a, b)` and `(b, a)` are different indexes, not duplicates.
