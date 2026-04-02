# Dagster Patterns

## Pipeline Architecture

Data flows through a layered schema model orchestrated by Dagster Cloud. A scheduled job runs every morning to update the financial database.

### Pipeline flow

```
Refinitiv QA ──(sling)──→ raw ──(dbt)──→ staging ──(dbt)──→ intermediate ──(python assets)──→ master
                                                                                                ↓
                                                                                              marts
```

| Step | Tool | Purpose |
|---|---|---|
| **raw** | Sling | Copy tables from Refinitiv QA source DB |
| **staging** | DBT | First transformation pass — source-dependent cleaning, typing, sanification |
| **intermediate** | DBT | Aggregation — join QA IDs to master IDs, produce final query results for master insertion |
| **master load** | Python Dagster assets | Insert/update master tables from intermediate results |
| **marts** | DBT | Aggregated views for consumption |

### Key distinctions

- **staging = source-dependent** — transformations specific to the data source (Refinitiv)
- **intermediate = source-agnostic** — aggregates, joins QA IDs to master IDs, produces final results
- **master tables are pre-built** — schema defined by SQLAlchemy entities, managed via Alembic migrations. The pipeline loads data into them, not creates them.
- **master load assets are custom Python** — not DBT, developed as Dagster Python assets

### Schema purposes

| Schema | Purpose | Managed by |
|---|---|---|
| `raw` | Raw copy from source DB | Sling (Dagster assets) |
| `staging` | Source-dependent cleaning and typing | DBT (Dagster assets) |
| `intermediate` | Cross-source aggregation, ID mapping, final results | DBT (Dagster assets) |
| `master` | Golden source — reference data, fundamentals, timeseries | SQLAlchemy entities + Alembic migrations (schema), Python Dagster assets (data load) |
| `marts` | Aggregated views for consumption | DBT (Dagster assets) |
| `data_quality` | Data quality check views | Dagster assets (materialized views) |
| `maintenance` | DB maintenance views | Dagster assets (materialized views) |

### View patterns

- **`_changes` views:** incremental — only new/modified records since last run. Used by daily ETL jobs.
- **`_full` views:** complete dataset. Used for backfills and initial loads.
- **`_full` and `_changes` views for the same table MUST apply identical transformation logic** (joins, filters, scaling, dedup, currency handling). When modifying one, always propagate changes to the other immediately. The only allowed differences are: CDC metadata columns (`sys_change_operation`, `sys_change_version`, `last_loaded_version`) and the CDC deduplication macro (`cdc_deduplicate`).
- When investigating daily job performance, focus on `_changes` views — they are what runs daily.

## Dual-Load Strategy (volumetric tables)

Large tables (market_data, std_financial_value, estimate_consensus — tens/hundreds of millions of rows) use two loading strategies.

### When to use dual-load vs simple truncate

- **Dual-load (CDC + full):** tables with millions+ rows where a daily full reload would take >10-15 min and stress indexes. Typically timeseries and fact tables that grow daily.
- **Simple truncate:** reference/dimension tables small enough to reload entirely in seconds (countries, currencies, items, periods, filings). No CDC needed.
- **Key signal:** if the daily job takes too long because of a table's volume, it's a candidate for CDC.

### Sling ingestion (raw)

| Strategy | Sling mode | Streams | Usage |
|---|---|---|---|
| CDC | `incremental` | `<Table>_Changes` streams, SQL Server `CHANGETABLE`, `update_key: SYS_CHANGE_VERSION` | Daily scheduled |
| Full load | `full-refresh` | `<Table>` streams with `chunk_size` for large tables | One-shot, on-demand |
| Reference | `truncate` | Small lookup tables (items, periods, filings, fx_rate) | Daily, complete reload |

### DBT views (staging → intermediate)

Each volumetric table has two intermediate views:
- `int_<domain>_changes` — reads from `stg_qa_<table>_changes`, deduplicates via `cdc_deduplicate` macro against `_load` tracking table
- `int_<domain>_full` — reads from `stg_qa_<table>`, no deduplication, complete dataset

### Master load (Python Dagster assets)

| Strategy | Loader | Config | Behavior |
|---|---|---|---|
| CDC (default) | `SimpleLoader` | `CDCConfig` with `tracking_table` | Single pass, reads from `_changes` view, updates `_load` tracking table |
| Full load | `BatchLoader` | `InsertConfig` with `BatchConfig` | Splits by date intervals (90d market, 30d financial), truncates before load, drops indexes/FK/unique during batch, recreates after |

- **CDC is the default** — runs daily, fast, incremental.
- **Full load requires double confirmation** — `full_load=True` + `confirm_full_load="YES"` in Dagster config. Used for initial loads and backfills.
- **Full load optimizations:** disable WAL, disable autovacuum, drop constraints during batch — recreate after completion.

### Tracking tables (`_load`)

Each volumetric table has a `<table>_load` companion in the master schema (SQLAlchemy model with `CDCLoadMixin`):
- Tracks `last_source_version` (SQL Server `SYS_CHANGE_VERSION`)
- Records `loaded_at`, `rows_inserted`, `rows_updated`, `rows_deleted`
- Used by `_changes` views to scope the next incremental load

### CDC setup on source DB

Before CDC can work, change tracking must be enabled on the source table in SQL Server:

1. Enable change tracking on the table:
   ```sql
   ALTER TABLE dbo.<Table> ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
   ```
2. Get the current version (use as initial version after a full load):
   ```sql
   SELECT CHANGE_TRACKING_CURRENT_VERSION() AS CurrentVersion;
   ```
3. Sling CDC stream queries the change table joined to the source:
   ```sql
   SELECT * FROM CHANGETABLE(CHANGES dbo.<Table>, {incremental_value}) ct
   JOIN dbo.<Table> t ON ct.<PK1> = t.<PK1> AND ct.<PK2> = t.<PK2>
   ```

The `{incremental_value}` is the last `SYS_CHANGE_VERSION` stored in the `_load` tracking table.

### When adding a new volumetric table

1. **Source DB:** enable change tracking on the source table (`ALTER TABLE ... ENABLE CHANGE_TRACKING`)
2. **Note the current version** (`CHANGE_TRACKING_CURRENT_VERSION()`) — use as initial version after first full load
3. Sling: add both `<Table>` (full-refresh + chunk_size) and `<Table>_Changes` (incremental + CHANGETABLE) streams
4. DBT staging: add `stg_qa_<table>` and `stg_qa_<table>_changes` views
5. DBT intermediate: add `int_<domain>_full` and `int_<domain>_changes` views (use `cdc_deduplicate` macro)
6. SQLAlchemy: add `<table>_load` model with `CDCLoadMixin`
7. Dagster asset: implement with `LoadModeConfig`, `SimpleLoader`/`CDCConfig` for CDC, `BatchLoader`/`InsertConfig` for full
8. **First run:** full load, then seed the `_load` tracking table with the noted version

## Asset Strategy

### Index management

- **raw schema:** indexes defined as Dagster assets — created/managed by pipeline code
- **master schema:** indexes defined in SQLAlchemy entities — managed via Alembic migrations

### Data quality and maintenance

- Materialized views in `data_quality` and `maintenance` schemas are Dagster assets
- Used for monitoring data integrity and DB health

## Job Definitions

- Pipeline definitions live in the `pipelines/` directory of the fundy project
- DBT models under `pipelines/dbt/`
- Master load assets are Python Dagster assets (not DBT)
- Dagster orchestration wraps DBT models + Python assets as a single daily scheduled job
