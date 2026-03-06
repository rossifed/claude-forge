---
description: "TimescaleDB patterns for Atonra: hypertables, compression, continuous aggregates, retention. Auto-activates for TimescaleDB codebases."
---

# TimescaleDB Patterns

## Hypertable Creation

- Create the regular table first, then convert: `SELECT create_hypertable('table', 'time_column')`.
- NEVER use `CREATE TABLE ... PARTITION BY` manually — let TimescaleDB manage chunks.
- Choose chunk interval based on query patterns:
  - Sub-second data → 1 day
  - Daily data → 1 week
  - Sparse/monthly data → 1 month
- Set chunk interval at creation: `create_hypertable('t', 'date', chunk_time_interval => INTERVAL '1 week')`.

## Compression

- Enable compression on hypertables for data older than an access threshold.
- `segmentby`: columns you filter/group by (typically the entity ID). Enables segment-level skipping.
- `orderby`: the time column, DESC. Enables efficient range scans within segments.
- Policy pattern:
  ```sql
  ALTER TABLE t SET (timescaledb.compress,
    timescaledb.compress_segmentby = 'instrument_id',
    timescaledb.compress_orderby = 'date DESC');
  SELECT add_compression_policy('t', INTERVAL '90 days');
  ```
- Compressed chunks are read-only. To update, decompress first, modify, recompress.
- Never compress data that's actively written to or frequently updated.

## Continuous Aggregates

- Use for pre-computed rollups (daily → weekly, tick → OHLCV).
- Define with `CREATE MATERIALIZED VIEW ... WITH (timescaledb.continuous)`.
- Refresh policy: `add_continuous_aggregate_policy(...)` with `start_offset` and `end_offset`.
- Continuous aggregates can be built on top of other continuous aggregates (hierarchical).
- Always include `time_bucket()` in the GROUP BY for the time dimension.

## Retention

- Use retention policies for data you no longer need: `add_retention_policy('t', INTERVAL '2 years')`.
- Retention drops entire chunks — it's fast and doesn't bloat. But it's irreversible.
- Combine with continuous aggregates: keep detailed data for 90 days, aggregated data forever.

## Query Patterns

- Use `time_bucket('1 day', date)` for time-based grouping — not `date_trunc`. `time_bucket` is TimescaleDB-optimized and works with chunk exclusion.
- Chunk exclusion: TimescaleDB skips chunks outside your WHERE time range. Always include a time range filter on the hypertable's time column.
- For "latest value per entity" queries, use:
  ```sql
  SELECT DISTINCT ON (instrument_id) instrument_id, date, value
  FROM t
  ORDER BY instrument_id, date DESC;
  ```
  With a composite index on `(instrument_id, date DESC)` this is fast.

## Anti-Patterns

- NEVER query a hypertable without a time range filter. Without it, all chunks are scanned.
- NEVER use vanilla PostgreSQL partitioning commands on a hypertable. TimescaleDB manages partitioning.
- NEVER set chunk intervals too small (creates excessive chunk overhead) or too large (loses chunk exclusion benefit).
