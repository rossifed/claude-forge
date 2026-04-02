# Estimate Segment Values (IBES) — Test Fixtures

Source: `master.estimate_segment_actual` and `master.estimate_segment_consensus` from Refinitiv IBES (`qa_TREProd*` tables)

## Test Panel

| Company | Currency | company_id | EstPermID | Edge case | External source |
|---|---|---|---|---|---|
| NVIDIA Corp | USD | 89814 | 30064850531 | Baseline, external source dispo | nvidianews.nvidia.com |
| Alibaba Group | CNY | 4587 | 30064871037 | Chinese company, many segments | — |
| Hermes International | EUR | 56397 | 30064885116 | European luxury, geographic segments | finance.hermes.com (blocked) |
| LSEG | GBP | 75350 | — | UK company, GBP subunit risk | lseg.com (blocked) |
| Bharti Airtel | INR | 16714 | 30064884874 | Indian telecom | — |
| Panasonic Holdings | JPY | 93191 | 30064879790 | Japanese conglomerate | — |
| KT Corp | KRW | 71752 | — | Korean telecom | — |

Note: EstPermIDs for LSEG and KT Corp not verified — use `stg_qa_estimates_mapping` to resolve from rkd_code.

## Raw Query Templates

### Actuals

```sql
SELECT pi."ProductBrandName" AS segment, a."PerEndDate"::date,
    round((a."DefActValue" * a."DefScale")::numeric, 0) AS raw_value,
    tc."Description" AS currency
FROM raw."qa_TREProdActRpt" a
JOIN raw."qa_TREProdInfo" pi ON pi."ProductID" = a."ProductID"
LEFT JOIN raw."qa_TRECode" tc ON tc."Code" = a."DefCurrPermID"::text AND tc."CodeType" = 7
WHERE a."EstPermID" = <est_perm_id>
AND a."PerType" = 4 AND a."Measure" = 20  -- annual Sales
AND a."PerEndDate" >= '<recent_date>'
ORDER BY pi."ProductBrandName", a."PerEndDate" DESC
```

### Consensus (latest per segment/period)

```sql
SELECT DISTINCT ON (pi."ProductBrandName", sp."PerEndDate")
    pi."ProductBrandName" AS segment, sp."PerEndDate"::date,
    round((sp."DefMeanKPI" * sp."DefScale")::numeric, 0) AS raw_mean,
    sp."NumKPI" AS num_estimates, tc."Description" AS currency
FROM raw."qa_TREProdSumPer" sp
JOIN raw."qa_TREProdInfo" pi ON pi."ProductID" = sp."ProductID"
LEFT JOIN raw."qa_TRECode" tc ON tc."Code" = sp."DefCurrPermID"::text AND tc."CodeType" = 7
WHERE sp."EstPermID" = <est_perm_id>
AND sp."PerType" = 4 AND sp."Measure" = 20
AND sp."PerEndDate" >= '<future_date>'
ORDER BY pi."ProductBrandName", sp."PerEndDate", sp."EffectiveDate" DESC
```

## External Sources

| Company | URL | What to extract |
|---|---|---|
| NVIDIA | `https://nvidianews.nvidia.com/news/nvidia-announces-financial-results-for-fourth-quarter-and-fiscal-2026` | Segment revenue by division (Data Center, Gaming, Prof Viz, Automotive) |

Note: IBES segments match the company's press release segmentation (Data Center, Gaming, etc.), unlike RKD which uses different groupings.

## Known Edge Cases

- **Value computation**: actuals use `DefActValue * DefScale`. Consensus uses `DefMeanKPI * DefScale`.
- **NormScale for actuals**: `NormKPIActValue * COALESCE(NormScale, 1)` — pipeline uses this path.
- **Currency lookup**: `TRECode.Code` is varchar, `DefCurrPermID` is integer — cast needed.
- **Consensus dedup**: Multiple `EffectiveDate` per (segment, period) — always take latest.
- **GBP subunit**: GBP companies may have `DefActValue * DefScale / 100` for GBp. The `estimate_subunit_factor` macro handles this. LSEG is a key test for this.
- **Segment naming overlap**: Some analysts use different segment names than the company (e.g., "Compute" + "Networking" vs "Data Center"). Both valid.
- **No ZAR/TRY/CHF**: these currencies had no segment estimate data at time of testing.

## Regression Values (validated 2026-04-01)

### NVIDIA (USD) — Actuals, Annual Sales, FY2024-2026

| Segment | FY2024 | FY2025 | FY2026 |
|---|---|---|---|
| Data Center | 47,525,000,000 | 115,186,000,000 | 193,737,000,000 |
| Gaming | 10,447,000,000 | 11,350,000,000 | 16,042,000,000 |
| Prof. Visualization | 1,553,000,000 | 1,878,000,000 | 3,191,000,000 |
| Automotive | 1,091,000,000 | 1,694,000,000 | 2,349,000,000 |
| OEM and other | 306,000,000 | 389,000,000 | 619,000,000 |
| **External (press release FY2026)** | — | — | **$215.9B total ✓** |

### Alibaba (CNY) — Actuals, Annual Sales, FY2025

| Segment | Value | Raw match |
|---|---|---|
| China E-commerce Group | 449,827,000,000 | ✓ exact |
| Intl Digital Commerce | 132,300,000,000 | ✓ exact |
| Cloud Intelligence | 118,028,000,000 | ✓ exact |
| Cainiao Logistics | 101,272,000,000 | ✓ exact |
| Local Services | 67,076,000,000 | ✓ exact |

### NVIDIA — Consensus, Annual Sales, FY2027-2029

| Segment | FY2027 mean | #Est |
|---|---|---|
| Data Center | 340,695,661,050 | 20 |
| Gaming | 15,388,856,110 | 20 |
| Automotive | 2,934,910,530 | 20 |
| Prof. Visualization | 4,708,857,220 | 20 |
