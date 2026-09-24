# Entity Geography, Entity Sub-type, Foreign-ownership Restriction (FactSet) — Test Fixtures

Source → master (migration `0023_geo_subtype_restriction`):
- `master.entity_country` ← `fds.ent_v1_ent_entity_coverage` 5 country roles (entity grain, every FDS-mapped entity)
- `master.entity.entity_sub_type_id` ← `ent_v1_ent_entity_coverage.entity_sub_type` (catalog `ref_v2_entity_sub_type_map`)
- `master.equity.foreign_restriction_type_id` + `sec_type_code` ← `fds.fp_v2_fp_sec_coverage.p_sec_type_code` @ `-R`
Target DB: `pg-factset-aws-prod`. Reference data, loaded daily by `etl__reference` (MERGE).

> Categorical data — no amount, no currency: the scaling / sub-unit / currency-panel method does NOT apply. Validate
> the MAPPING (entity, row presence, duplicates, code) on the FULL population, plus a public-facts panel.
> Resolve the panel **by name** (ids are dev-unpinned). Compare LIVE rows only: the MERGE parent template skips
> `deleted_at IS NOT NULL` rows, so soft-deleted rows legitimately keep NULL in the new columns.

## Test Panel (by name)

| Domain | Line / company | Expected | Edge case |
|---|---|---|---|
| sub-type | Enterprise Products, Energy Transfer, MPLX, Plains All American, Western Midstream, Cheniere Energy Partners, Sunoco, Alliance Resource | `ML` | listed MLPs |
| sub-type | Kinder Morgan Inc, ONEOK | `CP` | former MLP / C-corp — sub-type follows CURRENT status |
| geography | Accenture, Aon, Eaton, Johnson Controls, Medtronic | domicile IE, **risk US** | tax-inversion companies |
| geography | Seagate | domicile US, incorp IE, risk US | incorporation ≠ domicile |
| geography | Alibaba | domicile CN, incorp **KY**, risk CN | Cayman-incorporated |
| geography | TE Connectivity / Arch Capital | risk **US** but risk_revenue **CN** / **CA** | the two "risk" fields differ |
| restriction | Kweichow Moutai A `600519`, Ping An A `601318` | `PARTIAL` (09) | China A-shares |
| restriction | Ping An H `2318` | `NONE` (10) | same company, open class |
| restriction | PTT local `PTT` / NVDR `PTT.R` / ADR `PUTRY` | `PARTIAL` / `NONE` / `NONE` | Thai foreign cap; NVDR = foreigners' vehicle |
| restriction | Nestlé `NESN`, Apple `AAPL` | `NONE` | open baselines |

## Raw Query Templates (independent of the pipeline's staging / intermediate)

```sql
-- A. entity_country: master vs coverage, all FDS-mapped entities, 5 roles (codes outside master.country -> NULL)
WITH src AS (
  SELECT em.internal_entity_id AS entity_id, c.iso_country, c.iso_country_incorp, c.iso_country_cor,
         c.iso_country_top_georev, c.iso_country_cor_georev
  FROM master.entity_mapping em
  JOIN fds.ent_v1_ent_entity_coverage c ON c.factset_entity_id = em.external_entity_id::bpchar
  WHERE em.data_source_id = 2)
-- join master.entity_country (5 FKs -> master.country.code_alpha2) and count per-role IS DISTINCT FROM,
-- plus rows missing / extra on either side. Expect all 0.

-- B. sub-type: live entities
SELECT count(*) FILTER (WHERE est.mnemonic IS DISTINCT FROM NULLIF(btrim(c.entity_sub_type), '')) AS mismatch
FROM master.entity_mapping em
JOIN master.entity e ON e.entity_id = em.internal_entity_id AND e.deleted_at IS NULL
JOIN fds.ent_v1_ent_entity_coverage c ON c.factset_entity_id = em.external_entity_id::bpchar
LEFT JOIN master.entity_sub_type est ON est.entity_sub_type_id = e.entity_sub_type_id
WHERE em.data_source_id = 2;                                   -- expect 0

-- C. restriction: live equities, -S -> -R hop re-done via sym_coverage (NOT stg_fds_equity)
WITH x AS (
  SELECT frt.mnemonic AS master_level, eq.sec_type_code AS master_code, fp.p_sec_type_code AS src_code,
         CASE WHEN fp.p_sec_type_code = '08' THEN 'FULL' WHEN fp.p_sec_type_code = '09' THEN 'PARTIAL'
              WHEN fp.p_sec_type_code IS NOT NULL THEN 'NONE' END AS expected_level
  FROM master.equity eq
  JOIN master.instrument i ON i.instrument_id = eq.equity_id AND i.deleted_at IS NULL
  JOIN master.instrument_mapping im ON im.internal_instrument_id = eq.equity_id AND im.data_source_id = 2
  LEFT JOIN master.foreign_restriction_type frt ON frt.foreign_restriction_type_id = eq.foreign_restriction_type_id
  LEFT JOIN fds.sym_v1_sym_coverage sc ON sc.fsym_id = im.external_instrument_id::bpchar
  LEFT JOIN fds.fp_v2_fp_sec_coverage fp ON fp.fsym_id = sc.fsym_regional_id)
SELECT count(*) FILTER (WHERE master_level IS DISTINCT FROM expected_level) AS level_mismatch,
       count(*) FILTER (WHERE master_code IS DISTINCT FROM src_code) AS code_mismatch
FROM x;                                                         -- expect 0 / 0
```

## Known Edge Cases

- **`99`** in `iso_country_cor_georev` is a FactSet placeholder, not ISO → NULL (1 entity, 2026-09-24).
- **Restriction NULL ≠ NONE**: no FP coverage / no regional fsym → NULL (~211 k live equities). Never count NULL as
  unrestricted.
- **Only 08 / 09** carry a residency restriction in the 96-code `ref_v2_fp_sec_type_map` (exhaustive); the code
  taxonomy is FactSet-FP-specific (IDC lineage), not ISO/CFI.
- **Sub-type barely filled for funds** (~3 %) at the source — not a pipeline gap.
- **Soft-deleted rows** keep NULL in the new columns (MERGE skips them) — exclude them from mismatch counts.

## Regression Values (validated 2026-09-24, run fc573720)

| Anchor | Value |
|---|---|
| `entity_country` rows (= FDS-mapped entities in coverage) | 296 203; per-role mismatch 0 |
| role fill: domicile / risk / risk_revenue / top_revenue | 295 785 / 234 239 / 235 611 / 46 763 |
| live entities with sub-type check | 281 531, mismatch 0; `ML` = 98 |
| live equities restriction check | 593 306, mismatch 0; `FULL` 128, `PARTIAL` 17 341 |
| catalogs | `entity_sub_type` 28 rows; `foreign_restriction_type` NONE=1 / PARTIAL=2 / FULL=3 |
