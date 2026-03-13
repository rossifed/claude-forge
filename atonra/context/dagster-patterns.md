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
- When investigating daily job performance, focus on `_changes` views — they are what runs daily.

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
