# Financial Segment Values (FactSet) — Test Fixtures

Source: `master.financial_segment_value` from FactSet (`fds.ff_v3_ff_segbus_af` business + `ff_segreg_af`
geographic). Item catalog is FactSet-native (ids 1–6): `Segment Assets, Segment Capital Expenditures,
Segment Depreciation, Intersegment Revenue, Segment Operating Income, Segment Sales`.
Target DB: `pg-factset-aws-prod`. Companion RKD fixture: `segments-rkd.md` (legacy Refinitiv source).

> ⚠️ **company_id are DEV-UNPINNED** on `pg-factset-aws-prod` (not aligned to prod QA ids — see
> `project_fds_no_id_pinning_dev`). Resolve the panel **by name** (ids below are point-in-time, may change on
> a rebuild). Fundamental segments are **annual only** and **full-refresh** (no CDC).

## Test Panel (by name; company_id as of 2026-07-07)

| Company | Currency | company_id | Segments | Edge case | External |
|---|---|---|---|---|---|
| Amazon.com | USD | 6943 | 7 | Baseline large-cap; Σ = 100% of consolidated | ir.aboutamazon.com |
| Apple | USD | — (find by segment name 'iPhone') | product segments | iPhone FY2023 = $200.583B (10-K anchor) | apple.com/investor |
| Volkswagen AG | EUR | 131691 | 5 | EUR baseline | — |
| Shell Plc | GBP | 110933 | 6 | **GBP subunit risk** — must NOT be ×100 | shell.com (blocked) |
| Toyota Motor | JPY | 125196 | 3 | Large JPY numbers | — |
| Samsung Electronics | KRW | 106725 | 5 | Very large KRW (trillions) | — |
| Nestlé SA | CHF | 85945 | 7 | CHF | nestle.com |
| Reliance Industries | INR | 101996 | 5 | Large INR; slight intersegment (101.9%) | — |
| Heilongjiang Tianyouwei | CNY | 56173 | 5 | **FactSet SOURCE ERROR** — Σ segments ×~10,000 the real revenue | — |

## Raw Query Template (FactSet)

`master.value = ff_segbus_af.<field> × unit_factor` (all 6 measures `unit_factor = 1e6`). Resolve the
company to its primary fsym via `entity_mapping (ds=2)` + the `stg_fds_entity_primary` spine.

```sql
WITH fsym AS (
  SELECT DISTINCT COALESCE(sp.primary_regional_id, sp.primary_security_id) AS fsym_id
  FROM master.entity_mapping em
  JOIN staging.stg_fds_entity_primary sp ON btrim(sp.factset_entity_id) = btrim(em.external_entity_id)
  WHERE em.internal_entity_id = <company_id> AND em.data_source_id = 2 AND em.entity_type_id = 1
    AND COALESCE(sp.primary_regional_id, sp.primary_security_id) IS NOT NULL
)
SELECT btrim(b.label) AS segment, (b.sales * 1e6)::numeric AS raw_value, b.currency
FROM fds.ff_v3_ff_segbus_af b JOIN fsym f ON f.fsym_id = b.fsym_id
WHERE b.sales IS NOT NULL
  AND b."date" = (SELECT max(b2."date") FROM fds.ff_v3_ff_segbus_af b2 JOIN fsym f2 ON f2.fsym_id = b2.fsym_id)
ORDER BY raw_value DESC;
-- Master side: master.financial_segment_value JOIN financial_segment (name) JOIN financial_segment_item
--   WHERE segment_type_id=1 (business; =2 for ff_segreg_af geographic), item name = 'Segment Sales'.
-- Fields: sales/opinc/assets/capex/dep/interseg_rev. segbus has interseg_rev+ff_sic_code; segreg does not.
```

## Internal-coherence check (recommended for segments)

Σ(segment `sales`) should ≈ consolidated `ff_basic_af.ff_sales` (both ×1e6). Catches FactSet source errors.

```sql
-- ratio per fsym, latest year: seg_sum / consolidated; flag > 5x
```

## Known Edge Cases

- **Scaling**: all 6 measures `unit_factor = 1e6` (from `ref_v2_ref_metadata_fields`, `cur_indicator=1`).
- **GBP no subunit**: FactSet fundamentals are in the major unit — GBP segments are in £, NOT pence. Do NOT
  divide by 100 (unlike Refinitiv). Verified: Shell = £202.5B, not £20,251B.
- **`sales` = external-basis**: Σ segment sales reconciles to consolidated top line (~100%); `interseg_rev` is
  a separate item. Minor overlaps (Shell 103.7%, Reliance 101.9%) from trading eliminations.
- **FactSet SOURCE errors (~0.2%)**: 288 fsym (184 reaching a master company) have Σ segments > 100× the
  company's consolidated revenue (e.g. Heilongjiang Tianyouwei: 40,000 B vs 4 B CNY). NOT a pipeline bug —
  raw = master exactly. Obscure small-caps.
- **No stable segment id in FactSet**: `segment_id` is synthesized (`dense_rank` over fsym/type/label);
  `ff_segment_num` is an ephemeral size-rank. Identity anchor = the segment `label`.
- **Annual only**: no Quarterly/Semi-Annual (FactSet ships no `ff_segbus_qf/saf`).

## Regression Values (validated 2026-07-07)

| Anchor | Value | Note |
|---|---|---|
| Apple iPhone FY2023 (Segment Sales) | 200,583,000,000 USD | = 10-K, exact |
| Amazon / Samsung / Toyota / Nestlé / VW | Σ segments = 100.0% of consolidated | internal coherence |
| Global coherence (Σ/consolidated ∈ [0.8,1.2]) | 89.0% of 144,711 fsym | — |
| Gross source errors (> 100×) | 288 fsym / 184 companies (~0.2%) | FactSet source, documented |
| Raw→Master (8-currency panel incl. GBP) | exact | scale ×1e6, no pence bug |
