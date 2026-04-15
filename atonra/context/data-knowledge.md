# Data Knowledge

Connaissance acquise par exploration des données. Ce fichier est mis à jour
au fil des sessions de travail quand de nouvelles informations sont découvertes.

## Source Mappings

### Refinitiv → Master
<!-- À remplir lors de la prochaine session d'exploration -->

## Known Pitfalls

### master.std_financial_value unit conversion — FIXED (2026-03-25, pending full reload)

Refinitiv QA reports financial values with `UnitsConvToCode = 'M'` (millions). The DBT intermediate layer converts them to absolute values via the `convert_financial_value_units` macro (applies only for `item_precision IN (1, 2)`).

- **Fix applied**: DBT intermediate models now output the converted value directly as `value` (was `converted_value`), so the Python loader's name-based mapping picks it up automatically. The raw value is kept as `raw_value` for audit.
- **Status**: Fix deployed to DBT models. Requires a full reload (~1B rows, ~4h) to backfill corrected values in master. Until then, existing data still has raw millions.
- **After reload**: `master.std_financial_value.value` will contain absolute values — no downstream multiplication needed.

### master.estimate_actual NormScale not applied — FIXED (2026-03-26, pending full reload)

Refinitiv IBES estimates use `NormScale` to scale `NormActValue` to absolute values (e.g., NormScale=1000000 for monetary measures like Sales/Net Income, NormScale=1 for per-share like EPS).

- **Fix applied**: DBT intermediate models now multiply by `COALESCE(norm_scale, 1)` in the value computation. No SQLAlchemy/loader changes needed.
- **Status**: Requires full reload of `estimate_actual` (~42M rows).
- **After reload**: `master.estimate_actual.value` will contain absolute values.

### Percentages stored as whole numbers (precision=4), not as decimals

Refinitiv stores percentage values as whole numbers (e.g., 52 for 52%, not 0.52). These fall under `item_precision=4` which the conversion macro leaves untouched (factor=1). There is no flag in the source data to distinguish percentages from other ratios or operational KPIs — all share `precision=4`. A fix would require an item-level mapping to identify which `std_financial_item_id` values are percentages and divide by 100, but this is not feasible without a per-item semantic catalog.

- **Impact**: downstream consumers expecting normalized ratios (0.0–1.0) will get 0–100 for percentage items.
- **Workaround**: handle at consumption layer, per item, when the semantic is known.

## Value Formats & Conventions

### Refinitiv ItemPrecision codes

| Precision | Meaning | Unit handling |
|---|---|---|
| 0 | Counts, flags, physical volumes | No conversion (correct) |
| 1 | Monetary amounts (Revenue, Net Income, etc.) | Converted to absolute (after reload) |
| 2 | Share counts (Shares Outstanding, etc.) | Converted to absolute (after reload) |
| 3 | Per-share values (EPS, DPS, etc.) | No conversion (correct) |
| 4 | Ratios, %, operational KPIs | No conversion (correct) |

## Operational Runbooks

### Historical market_data backfill for specific quotes

Use when quote_ids need their historical `master.market_data` populated outside
the normal CDC flow. Common cases:
- Post-fix that unlocks previously-masked quotes (staging dedup change, constraint relaxation)
- A specific instrument / set of quotes whose history needs to be rebuilt
- Gaps in `master.market_data` for quote_ids that have data in Refinitiv source

**Persistent artifacts in prod** (created 2026-04-13, kept alive for reuse):
- `master.tmp_new_quotes` — temp table with a single column `quote_id`. The
  procedure joins to it to scope the backfill. Can be truncated/refilled freely.
- `master.backfill_recovered_market_data()` — PL/pgSQL procedure that loops
  2026 → 2000 year-by-year, reads from `intermediate.int_market_data_full`
  joined to `master.tmp_new_quotes`, inserts into `master.market_data` with
  `ON CONFLICT (trade_date, quote_id) DO NOTHING` (idempotent).

**Standard procedure:**

1. Scope: fill `master.tmp_new_quotes` with the target quote_ids.

   ```sql
   TRUNCATE TABLE master.tmp_new_quotes;

   -- Example: backfill a single instrument
   INSERT INTO master.tmp_new_quotes (quote_id)
   SELECT quote_id FROM master.quote
   WHERE instrument_id = <target> AND deleted_at IS NULL;

   -- Example: backfill all quotes above a watermark (post-fix recovery)
   INSERT INTO master.tmp_new_quotes (quote_id)
   SELECT quote_id FROM master.quote
   WHERE quote_id > <watermark> AND deleted_at IS NULL;

   SELECT COUNT(*) FROM master.tmp_new_quotes;  -- sanity check
   ```

2. Run the procedure:

   ```sql
   CALL master.backfill_recovered_market_data();
   ```

   Timing rules of thumb (Hetzner-class, prod-class similar):
   - ~5-10 min per year for ~100k quote_ids
   - Seconds for a handful of quotes
   - Scales roughly linearly with `nb_quotes × nb_years_with_data`

3. Verify (sample target instrument/venue) then cleanup:

   ```sql
   DROP TABLE master.tmp_new_quotes;  -- optional; safe to keep between uses
   ```

**Properties:**
- **Idempotent.** `ON CONFLICT DO NOTHING` → re-runs and overlaps are free.
- **Checkpointed.** `COMMIT` between each year in the procedure body, so a crash
  mid-backfill doesn't rollback completed years.
- **Safe for quotes without source data.** Join to `int_market_data_full` →
  0 rows produced, no harm.
- **Does NOT cover `total_return`.** An equivalent procedure
  (`master.backfill_recovered_total_return`) using `int_total_return_full` can
  be created with the same shape; not deployed in prod as of 2026-04-15.

**What this is NOT for:**
- Recent CDC gaps (use the normal daily CDC pipeline, not this)
- Non-market_data tables (needs a dedicated procedure)
- Fixing data quality issues at row level (this just replays source as-is)

**Origin:** Created 2026-04-13 for the ~114k recovered quotes from the
`stg_qa_quote` secondary-listings fix. Reused 2026-04-15 for ~3.2k additional
quotes exposed by the `master.quote` partial-unique constraint relaxation.
