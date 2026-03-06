---
description: "Atonra database modeling conventions: naming, column types, referential integrity, time series patterns. Auto-activates for database work."
---

# Atonra Data Modeling Conventions

## Naming

- Tables: `schema.entity_name` (snake_case, singular). Example: `mart.fund_nav`, `ref.currency`.
- Columns: `snake_case`. No table-name prefix on columns (`date` not `nav_date`, except when disambiguating joins).
- Schemas by layer:
  - `raw` — landing zone, untransformed source data
  - `stg` — staging, cleaned and normalized
  - `int` — intermediate, business logic applied
  - `mart` — consumption-ready, optimized for queries
  - `ref` — referential data (golden source)
  - `portfolio` — portfolio management domain

## Column Types

- Instrument identifiers: `UUID` with FK to `ref.instrument`.
- Portfolio identifiers: `UUID` with FK to `ref.portfolio`.
- Dates (calendar concepts): `DATE`, never `TIMESTAMP`. Market data is date-granular.
- Timestamps (events): `TIMESTAMPTZ`, always with timezone.
- Prices: `NUMERIC(18,8)`.
- NAV values: `nav_per_share NUMERIC(18,8)`, `total_nav NUMERIC(22,4)`.
- Weights / percentages: `NUMERIC(10,8)` in decimal form (0.05 not 5.0).
- Currency codes: `CHAR(3)` (ISO 4217). FK to `ref.currency` when available.
- Source identifiers: `VARCHAR(50)` for external system IDs (Bloomberg ticker, ISIN, etc.).
- Boolean flags: `BOOLEAN` with `NOT NULL DEFAULT false`.

## Time Series Tables

- Natural key: `(instrument_id, date)` for daily data, `(instrument_id, timestamp)` for intraday.
- Always include a `loaded_at TIMESTAMPTZ DEFAULT now()` for auditing.
- Standard price table columns: `open`, `high`, `low`, `close`, `volume`, `adjusted_close`.
- Every time series table carries a `source VARCHAR(20)` column to track data provenance.

## Referential Data (Golden Source)

- `ref.instrument` is the single source of truth for instrument identity.
- All instrument-related tables FK to `ref.instrument(id)`.
- Referential tables are append-only with `valid_from`/`valid_to` for temporal versioning (SCD Type 2).
- Currency must always accompany any monetary value — never assume a default currency.

## Constraints

- Unique constraints on natural keys (not just primary key on surrogate).
- FK constraints enforced in `ref` and `mart` schemas. Optional in `raw`/`stg` (source data may be dirty).
- `NOT NULL` on all columns except where NULL has explicit business meaning (e.g., missing market data on holidays).

## Anti-Patterns

- NEVER store financial amounts without their currency.
- NEVER use `TIMESTAMP` (without timezone) for event data.
- NEVER use `FLOAT`/`DOUBLE` for monetary values or weights.
- NEVER create a table without specifying which schema it belongs to.
