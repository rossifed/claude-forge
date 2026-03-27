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
