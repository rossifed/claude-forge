# Data Knowledge

Connaissance acquise par exploration des données. Ce fichier est mis à jour
au fil des sessions de travail quand de nouvelles informations sont découvertes.

## Source Mappings

### Refinitiv → Master
<!-- À remplir lors de la prochaine session d'exploration -->

### FactSet symbology → primary resolution (entity → -S → -R → -L)

FactSet identifiers (`fsym_id`) carry a 2-char suffix denoting their level (doc:
Daily Prices V2): `-S` security, `-R` regional, `-L` listing. `sym_v1_sym_coverage`
is the navigation HUB — one row per `fsym_id` at every level, each row carrying
`fsym_security_id` (-S) and `fsym_regional_id` (-R) pointers. FactSet's own example
queries navigate via these columns (confirmed in Daily Prices V2 & Fundamentals V3).

**Data grains (doc-confirmed):**
- Prices → `-R` (regional) level.
- Fundamentals (`ff_*`) → `-R` OR `-S` level ("Fsym_id can be represented at either").
- Listing `-L` → prices/exchange only; never used for fundamentals.

**Entity primary resolution (the pure spine):**
- Entity's primary equity = `sym_coverage.fsym_primary_equity_id`. Verified CONSTANT
  per entity (0 entities with >1 distinct value) → no ranking needed, just read it.
- `-S` → `-R`: read `fsym_regional_id` on the primary security's coverage row.
- `-R` → `-L`: read `fsym_primary_listing_id` on the REGIONAL row (+ `fref_listing_exchange`).
- Build with `DISTINCT` + double `LEFT JOIN sym_coverage` (PK = fsym_id → no fan-out,
  1 row per entity). NO security-type whitelist, NO active_flag, NO ROW_NUMBER — the
  spine must stay decoupled from downstream equity/company filters.

**Gotchas (verified on pg-factset-aws-prod):**
- `fsym_primary_listing_id` on a `-S` row is NOT a listing: it equals the `-R` (when
  the security has a regional) or NULL (when it doesn't). The real `-L` is only on the
  regional row. ⇒ no regional ⇒ NO listing reachable; a "read `-L` from the -S row"
  fallback recovers 0 (tested). Those securities are genuinely listing-less (OTC/delisted).
- ~22% of primary securities have no `-R` (regional NULL) — intrinsic FactSet, not a filter.
- Reading fundamentals only at `-R` misses securities whose fundamentals sit at `-S`
  (~7 PUB entities with NULL regional). Doc-conform fix = try `-R`, fallback `-S`.
- One primary security can be shared by several entities (holding/opco/group, max 17
  observed = Geodyne Energy LP family, all PVT). LEGITIMATE: replicating prices/
  fundamentals to all sharing entities matches FactSet's model. Uniqueness holds only
  at entity grain, never at security/regional.

### Legacy (Refinitiv/QA) ↔ FactSet ID mapping (crosswalk)

Mapping the current QA master universe to the new FactSet master (for cutover ID
realignment + coverage continuity). QA master is identifier-rich (~all of 61 664
equities carry ISIN/CUSIP/SEDOL/RIC/ticker); FactSet is the limiting side.
Co-locate by snapshotting QA into the FactSet DB (`migration.legacy_master_instrument`,
1 row per QA security). Match at security grain, roll up to company.

**CUSIP format trap (CRITICAL):** QA stores **CUSIP-8** (no check digit), FactSet
`fds.sym_v1_sym_cusip` stores **CUSIP-9** (with check digit). Naïve `cusip = cusip`
→ **0 matches**. Correct join: `left(btrim(fds.cusip), 8) = btrim(qa.cusip)`
(the 9th digit is derived → left-8 is 1:1, no collision). This single bug looked
like a "20k missing companies" coverage hole; it was a format false-negative.

**Waterfall (deterministic, security grain, all keys at `-S`, unique → no fan-out):**
ISIN current (`sym_v1_sym_isin`) → ISIN hist (`sym_v1_sym_isin_hist`) → CUSIP-8.
Result: 42 238 → +14 → +18 987 → **425 unmatched (0.7 %)**. `btrim()` both sides
(FactSet `character` cols are space-padded). SEDOL unusable (no FactSet table).

**Rollup `fsym (-S) → sym_v1_sym_sec_entity (factset_entity_id) → master.entity_mapping
→ master.company`:** 99.3 % of QA companies have a matched security, but only
**90.7 % (54 520/60 077) resolve into `master.company`**. The ~8.5 % shortfall is
NOT missing securities — the security resolves to a FactSet entity OUTSIDE our
PUB perimeter (`sym_v1_sym_entity.entity_type`): funds/ETFs (MUE/MUC/… ~1 670 —
correct exclusion), subsidiaries/holdings (SUB/HOL ~1 440 — parent usually PUB,
consolidation), private/external (PVT/EXT ~2 200 — perimeter question). This is
the Refinitiv-vs-FactSet modeling difference (QA models ADRs/funds as standalone
companies; FactSet does not). FactSet entity hierarchy = `ent_v1_ent_entity_structure`;
QA's own parent link = `master.company.primary_company_id`.

### FactSet price feed — FGP vs FP, history window & survivorship

Two FactSet daily-price products, different grain/source/depth:
- **FGP** (`fgp_v1_fgp_global_prices`, `-R` and `-L`): consolidated price + volume + **vwap** +
  turnover/trade_count/returns. **History floor = 2006-01-03 (hard, whole table).** Chosen feed,
  read at `-R` (reproduces today's Refinitiv master to the share). See market-data migration docs.
- **FP basic** (`fp_v2_fp_basic_prices`, `-R` only): close/o/h/l/volume, **no vwap**, source IDC.
  History back to **1972**.

**Coverage at our quote universe (`-L`, data_source_id=2, 141 102 quotes; pg-factset 2026-06-09):**
- FGP `-R` primary = 79.0 %; **FGP `-L` fallback** (no `-R` composite) = +11.3 % → **FGP total 90.3 %**.
- The "FP-only `-R`" set (~15k) is NOT temporality and NOT mainly delisting: **84 % post-2006, 79 %
  active** — live securities without an FGP `-R` composite, fully recovered by the **FGP `-L` fallback**.

**Survivorship (`sym_v1_sym_coverage.active_flag`):** FGP is NOT live-only — it **retains 70.3 % of
delisted** quotes (post-2006 deaths kept). Adding FP rescues only +3 205 quotes (2.3 %); FP's
*irreplaceable* contribution = **~667 quotes that lived & died entirely before 2006** (629 delisted).
The remaining gap (~10.4k quotes, ~70 % warrants/preferred/DRs) is **unpriced in ANY FactSet product**
— a hard FactSet limit, not a product-choice artifact. ⇒ Use FGP `-R` + `-L` fallback; FP deferred.

**Bridge `-L → -R`:** `sym_v1_sym_coverage.fsym_regional_id` (100 % of quotes resolve).

### FactSet fundamentals & estimates — model, subscription & per-item scaling

Migrating `master.std_financial_*` (statements) + `master.estimate_*` (consensus/actuals) from
Refinitiv (RKD/IBES) to FactSet. Full analysis in `src/data/docs/factset-migration/fundamentals/`.
Verified on `pg-factset-aws-prod`, 2026-06-09. `data_source` FDS=2 (QA=1).

**Shape — the structural delta:**
- **Fundamentals `ff_v3` = WIDE / pivoted.** One row per security×fiscal-period (`PK fsym_id,date`);
  **each line item is its own COLUMN** (`ff_sales`, `ff_net_income`…). No per-row item code, **no
  filing/statement decomposition**, no statement_type. ⇒ migration must **unpivot** ~130–700 columns
  into long `(item,value)` rows AND **synthesize** the filing/statement layer from the item→statement
  map (`ff_financial_stmt_map` / `ff_balance_model`). Subscription = **Basic + Advanced + segments
  only** (NO Industry-Metrics / Banks / Officers → no long/EAV table). Frequencies = separate tables
  (AF/QF/SAF/LTM/YTD); restatements = parallel `_R_` tables (PIT = `COALESCE(_R_, base)`).
- **Estimates `fe_v4` = consensus-only** (`conh`+`act`+`guid`; NO broker detail, NO smart estimates).
  Measure = string mnemonic `fe_item` (`EPS`,`SALES`); period = `fe_fp_end` + `fe_per_rel`;
  effective-dated (`cons_start_date`/`cons_end_date`, NULL=current). No `fye_month`/`fiscal_year`
  cols → derive. Fundamentals at `-R`/`-S`, estimates at `-R` (reuse `sym_v1_sym_coverage` spine).

**Per-item SCALING (critical — confirmed on Apple, both sides):** values are **NOT absolute** and
**NOT a fixed millions convention**. FactSet ships a **per-item scale factor**, rule:
> `absolute_value = stored_value × unit_factor`
- Fundamentals: `ref_v2_ref_metadata_fields (table_name, field_name → unit_factor, cur_indicator,
  split_indicator)`. On `ff_basic_af`: monetary & share-counts `unit_factor=1e6`, per-share/ratios
  `=1` (15 control cols NULL). Verified: `ff_sales` 383 285×1e6=$383.285 B, `ff_eps_basic` 6.16×1.
- Estimates: `ref_v2_fe_item_map (fe_item → unitfactor, curindicator, splitindicator)`. Highly
  non-uniform: `{0.01, 1, 1e3, 1e6, 1e7, 1e9}` (0.01 ⇒ some measures percent-scaled — inspect).
  Verified: `SALES` actual 383 285×1e6, `EPS` 6.13×1.
- ⇒ FactSet analogue of Refinitiv `ItemPrecision`/`UnitsConvToCode` (fund) + `NormScale` (est), but
  **cleaner**: one ready multiplier per item via a metadata JOIN. The `× unit_factor` multiply
  **stays** in the pipeline (do NOT "load directly"); only its source changes. **Lesson: two wrong
  assumptions ("already absolute", then "fixed millions") were caught only by empirical check —
  always sample a known large-cap before trusting a scale claim.**

**Other migration notes:** master catalog IDs (`std_financial_item_id`, `period_type_id`,
`statement_type_id`, `estimate_item_id`) = **literally the Refinitiv source codes today** → FactSet
mnemonics force a catalog re-key (the dormant `std_financial_item_mapping` is the intended bridge).
`currency` on `ff_*` = trading currency (AMBIGUOUS vs filing ccy — verify). FactSet FX table
`ref_v2_fx_rates_usd` **not subscribed**.

### GICS classification — FactSet does NOT provide it; curated snapshot + ISIN→CUSIP bootstrap

GICS is licensed (MSCI/S&P) and **absent from the FactSet feed** (FactSet's `industry_code`-style
field = a 6-bucket financial-template `BNK/FIN/IND/INS/TRN/UTL`, NOT a sector classification). So GICS
is **master-owned reference data**, not a provider feed. Full doc:
`src/data/docs/factset-migration/A-referential/classification/gics-classification.md`.

- **Structure** (scheme/level/node tree, 273 nodes = current GICS) = static dbt seeds; master is the
  golden source (feeds workbench, not the reverse). `int_classification_*` read the seeds, GICS-only,
  `scheme_id`=1, node `level_number` derived from code length (2/4/6/8→1/2/3/4). Themes (scheme 101+)
  = separate workbench stream, deferred.
- **Company→GICS** = a **Refinitiv-built snapshot** (`reference/gics_classification.csv`, 54,310 valid
  ISINs), NOT the workbench `wb_classification_instruments` (only ~6.6k favorites, unused in prod). Prod
  `entity_classification` GICS already comes from this S3 file.
- **Bootstrap = one-shot ISIN→CUSIP waterfall** → resolve to OUR `entity_id`, then freeze as a curation
  seed (`curation.gics_company_mapping(entity_id, gics_sub_industry_code, source)`, keyed by the id we
  own → no runtime ISIN dependency; ISIN may not persist in the FactSet feed). Path: `sym_v1_sym_isin`
  → `sym_v1_sym_sec_entity` → `entity_mapping`(ds=2) → company (deterministic 1:1, no fan-out); CUSIP
  fallback for ISINs absent from FactSet (27%!) via `migration.legacy_master_instrument.cusip` (CUSIP-8)
  → `migration.fds_cusip8_lookup`. ISIN-only=38,421; +CUSIP=**50,354** (≈prod 50,533, 0.35% gap = hard
  FactSet universe limit). Historical ISINs rejected (+86 but 8× conflicts). `int_entity_classification`
  = straight projection of the seed (validate entity+node), **conflicts EXCLUDED never guessed**.
- **Mnemonic standardized `GICSCLAS`→`GICS`** (only 2 code refs; unifies `company_enriched` which
  already used 'GICS'; frontend agnostic via `/api/data/gics`).
- **`curation` pattern (reusable):** dedicated `curation` schema = future operational table name (loader
  `source_table` never changes); keyed by an id we own; `source` provenance column; git CSV = v0 store.
  Same pattern for any manually-managed master input (cf. `entity_filter_override`).

### FactSet region taxonomy vs Atonra `master.region` — DIVERGENT, do NOT auto-map

`master.country_region` is **provider-agnostic Atonra IP**, not provider data. Source = a bespoke
investment-region matrix (`seed.regions_master`, ex-`raw.s3_regions_master`): Developed/Emerging/
Frontier (market classification) + Americas/EMEA/APAC/Standalone/BRICS/MENA/Eurozone/Europe/LatAm.
Many-to-many (a country sits in several). Migrated as a **dbt seed** (98 countries × 12 flags) → the
co-located build carries no Sling/S3 dependency. `int_country_region` unpivots the seed + resolves ids
at master; `stg_s3_country_region` deleted (seeds skip staging). Validated: 284 rows, fingerprint
**identical** to Refinitiv prod `master.country_region`.

**FactSet HAS an overlapping country×region matrix but it is NOT a drop-in replacement:**
- `fds.ref_v2_econ_country_inclusion` (iso_country × {developed, emerging, frontier, **bric**, eurozone,
  eu15/eu27, g7, g20, gcc, opec, oecd, asean, …}) + `fds.ref_v2_country_map` (iso_country → geographic
  region A/E/F/L/M/N/Y = Asia/Europe/Africa/LatAm/MidEast/NorthAm/Pacific). Also `fds.ref_v2_region_map`
  (geo lookup), `fds.sym_v1_sym_region` (security→geo region).
- **Verified divergences (adopting FactSet would CHANGE master values):** FactSet `bric` excludes South
  Africa (BRIC=4; Atonra BRICS includes ZA); FactSet classes Saudi Arabia **Frontier**, Atonra **Emerging**.
- **No FactSet equivalent** for `Standalone` (portfolio concept), nor the composites `Americas`/`EMEA`/
  `APAC`/`MENA` (would need bespoke composition from geo codes).
- ⇒ Seeded to preserve exact prod semantics. FactSet `ref_v2_econ_country_inclusion` = candidate
  **future-refresh** source for the market-classification dimension only, NEVER an automatic 1:1 map.

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
