# Data checklist (Dagster · dbt · DB · serving)

Doctrine references (authoritative, loaded in context — verify against them): `dagster-patterns.md` (layers, dual-load, `_full`/`_changes` parity), `data-access-conventions.md` (placement tests, read-vs-produce), `master-schema.md`, `data-knowledge.md` (source mappings, known traps), skill `database-modeling` (types, sizing, keys).

## Read in layers (source → consumer)

A defect in one layer usually shows as a contradiction with the next. Read in this order:

| Layer | Files (fundy) | Its ONLY job |
|---|---|---|
| Raw | `sling/**`, `dlt_pipelines/**` | Faithful copy of the source. No transformation. |
| Staging | `dbt_project/models/staging/stg_<src>_*.sql`, `sources.yml` | Source-dependent cleaning, typing, per-item scaling (metadata JOIN). Provider ids and provider vocabulary confined here. |
| Intermediate | `dbt_project/models/intermediate/int_*.sql` | Source-agnostic: resolve provider ids → master ids (`*_mapping` + `data_source_id`), aggregate, produce the exact rows master receives. One feeder per master target. |
| Master schema | `src/data/data/db/models/*.py`, `alembic/versions/*` | Normalized golden source, constraints. |
| Master load | `etl/master/assets/loading/*.py`, `jobs/**`, `schedules/**` | Load intermediate → master with the right mode. |
| Serving | `dbt_project/models/serving/*.sql`, `serving/**` | Denormalized, consumer-shaped read models. |
| API | `data/api/routes/**`, `services/**`, `schemas/**` | Parameterized reads matching the physical read path. |

Finding pattern: work done in the wrong layer (scaling in intermediate, id resolution in staging, business filter in raw, provider id reaching master/serving).

## Placement — is this the right home?

Challenge every NEW table, column, or dataset with the three tests of `data-access-conventions.md`, stop at first fail:
1. **Cycle** — computed FROM master data (ratios, scores, metrics)? → not master (serving / ClickHouse `signals`).
2. **Domain** — app operational state? → its service, not master.
3. **Source contract** — source-grade guarantees? Fast-evolving algorithmic output → serving-composed.

Also: does it duplicate an existing table/column/view that already holds the same fact? Is master normalized (no repeated denormalized attributes, no derived columns that can drift from their source)?

## Data model vs business

- The model answers the actual need: grain stated and correct (one row per what?), keys match that grain, nothing the consumer needs is missing, nothing is stored "just in case".
- Constraints on master: PK, FK to reference tables, NOT NULL where the business guarantees presence, UNIQUE on natural keys, CHECK where a domain is closed. FK-free fact tables are OK **only** if integrity is guaranteed by pipeline inner joins AND the serving twin carries the FKs — state it explicitly.
- Temporal versioning: master tables with `temporal_tables` have their `_history` twin and trigger in the migration.
- Migration: additive and reversible where possible; chained correctly to siblings (`down_revision`); renames/drops go two-phase so live consumers never break (prod is live — see memory).

## Types & sizing (overflow)

- Each column type justified against the source spec AND actual data (query `max(length())`, `max(abs(value))`, cardinality). Follow `database-modeling`.
- Overflow risks: `integer` on ids/counts/volumes that can exceed 2.1 B, `smallint` on a growing catalog, `numeric(p,s)` too narrow for absolute values after `× unit_factor` (millions → absolute adds 6 digits), `varchar(n)` shorter than the source.
- No `float`/`double` for monetary values.
- Scale/unit semantics documented and applied once (never twice across layers).

## Source semantics (fds.* and any provider table)

- The value comes from the right table AND column, at the right grain/level (FactSet `-S`/`-R`/`-L`; entity vs security). Check `data-knowledge.md` for the known traps of that source (CUSIP-8 vs 9, `ent_mv` vs `ent_mv_ex_treasury`, `bpchar` padding, per-item `unit_factor`, pence vs major unit, adjusted vs as-reported).
- Semantics confirmed from provider docs (`~/Documents/<Provider>/`) or metadata tables, not inferred from a column name. If unconfirmed → Open question.
- Validate on a known large-cap (and a discriminating case — e.g. treasury-heavy) that the loaded value matches the source × scale.

## ID stability

- Ids created by the pipeline are stable across reloads and across source growth.
  - 🔴 pattern: `row_number() over (order by <source item>)` / `dense_rank()` / sequence assignment ordered on source data → a new source item shifts every following id; FKs and consumers silently re-point.
  - Stable alternatives: the source's natural key, a mapping table that assigns an id once and never reassigns (`*_mapping` pattern), a deterministic hash of the natural key.
- A resolved key never flips to nullable; resolved facts don't carry provider ids (isolated in a mapping/`_unresolved` table only when they are the sole handle, justified).

## Load mode & downstream objects

- Mode matches volume and change pattern: CtasSwap / truncate-insert (small or full rebuild), CDC upsert/merge (volumetric, daily deltas), batch full load (backfill, double-confirmed). A daily full rebuild of a large table, or a merge on a table with no unique key, is a finding.
- **Dependent views:** any swap/rename/`DROP … CASCADE`/dbt full-refresh drops dependent views. Enumerate dependents (`pg_depend`, dbt graph) and verify they are recreated in the SAME run; otherwise flag the risk of losing downstream views, naming them.
- Rebuild restores PK/FK/indexes/NOT NULL (e.g. `CtasSwapConfig.from_model`).
- dbt `_full`/`_changes`: identical transformation logic; only CDC metadata + `cdc_deduplicate` may differ. A `_full`-only table must not reference a nonexistent `_changes`.
- Stale dbt manifest: after staging edits, `dbt parse` + code-location reload before any run.

## Orchestration — nothing orphan

- Every new asset is reachable from a scheduled job (daily/weekly) or explicitly documented as manual (backfill) with a reason. An asset materialized once by hand and never scheduled = 🟠 (it will silently go stale).
- AssetKey namespaced per layer (`staging.<src>.<domain>` → `intermediate.<domain>` → `master.<domain>` → `serving.<domain>`), group set, keys match `sources.yml` `dagster.asset_key`.
- Deps declared for every mapping/catalog read during resolution; ordering guarantees the upstream is fresh.
- Concurrency key shared between jobs writing the same table (CDC vs full).

## Serving exposure

- New master data that consumers need is exposed in serving (and in the API if it's a product field); provider ids not leaked.
- Serving reads master, never another copy; pipelines never read serving.

## Performance

- Joins on indexed keys with matching types (`bpchar` vs `text` mismatch or `btrim(indexed_col)` kills the index → seqscan).
- No row-by-row loops where a set-based statement works; no correlated subquery per row on large tables (prefer `LATERAL … LIMIT 1` with a supporting index for as-of joins).
- Range joins (`BETWEEN` on intervals) on large tables → check cardinality blow-up.
- Filters that the API/consumer advertises have a supporting index on the target table.
- When perf is uncertain: do NOT conclude — put the exact `EXPLAIN` (without `ANALYZE`) in Open questions, or run it via MCP if it is plan-only and cheap.

## Tests

- dbt tests on keys (unique, not_null, relationships) of new models, at least on small feeders.
- Python loaders/assets: unit tests on the pure parts (query building, row mapping).
- Propose (do not run) a `data-validation` pass on affected master tables after the load.
