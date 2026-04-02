# Financial Segment Values (RKD) — Test Fixtures

Source: `master.financial_segment_value` from Refinitiv RKD (`qa_RKDFndBGSeg*` tables)

## Test Panel

| Company | Currency | company_id | RKD Code | Edge case | External source |
|---|---|---|---|---|---|
| NVIDIA Corp | USD | 89814 | 11997 | Baseline, large-cap tech | nvidianews.nvidia.com (press releases) |
| Alibaba Group | CNY | 4587 | 95556 | Chinese conglomerate | — |
| Hermes International | EUR | 56397 | 19344 | European luxury, geographic segments | finance.hermes.com (blocked) |
| LSEG | GBP | 75350 | 27137 | UK company, GBP subunit risk | lseg.com (blocked) |
| Bharti Airtel | INR | 16714 | 29200 | Indian telecom, many segments | — |
| Panasonic Holdings | JPY | 93191 | 23500 | Japanese conglomerate, many segments | — |
| KT Corp | KRW | 71752 | 30534 | Korean telecom, very large numbers | — |
| Cosan SA | BRL | 30100 | 49678 | Exotic currency, fractional millions | — |
| Airports of Thailand | THB | 3588 | 38007 | Exotic currency, small segment values | — |
| JPMorgan Chase | USD | 67755 | 14613 | Bank — no Total Revenue, uses NII (item 14) | jpmorganchase.com (blocked) |

## Raw Query Template

```sql
SELECT seg."SegDesc" AS segment, v."PerEndDt"::date AS period_end,
    v."Value_" AS raw_value, qrspf."UnitsConvToCode" AS units, convccy."Desc_" AS currency
FROM raw."qa_RKDFndBGSegVal" v
JOIN (SELECT DISTINCT "Code","PerEndDt","PerTypeCode","StmtDt","SegTypeCode","SegOrder","SegID"
      FROM raw."qa_RKDFndBGSegData") sd
    ON sd."Code"=v."Code" AND sd."PerEndDt"=v."PerEndDt" AND sd."PerTypeCode"=v."PerTypeCode"
    AND sd."StmtDt"=v."StmtDt" AND sd."SegTypeCode"=v."SegTypeCode" AND sd."SegOrder"=v."SegOrder"
JOIN raw."qa_RKDFndBGSeg" seg ON seg."Code"=v."Code" AND seg."SegID"=sd."SegID"
JOIN raw."qa_RKDFndStdPerFiling" qrspf ON qrspf."Code"=v."Code" AND qrspf."PerTypeCode"=v."PerTypeCode"
    AND qrspf."PerEndDt"=v."PerEndDt" AND qrspf."StmtDt"=v."StmtDt"
JOIN raw."qa_RKDFndCode" convccy ON convccy."Code"=qrspf."CurrConvToCode" AND convccy."Type_"=58
WHERE v."Code"::text = '<rkd_code>' AND v."PerTypeCode" = <period_type> AND v."SegTypeCode" = 1
AND v."Item" = <item_id>
AND v."PerEndDt" = (SELECT MAX(v2."PerEndDt") FROM raw."qa_RKDFndBGSegVal" v2
    WHERE v2."Code"::text='<rkd_code>' AND v2."PerTypeCode"=<period_type> AND v2."SegTypeCode"=1 AND v2."Item"=<item_id>)
ORDER BY v."Value_" DESC
```

Items: 8 = Total Revenue, 14 = Net Interest Income (banks), 32 = Income Before Tax

## External Sources

| Company | URL | What to extract |
|---|---|---|
| NVIDIA | `https://nvidianews.nvidia.com/news/nvidia-announces-financial-results-for-fourth-quarter-and-fiscal-2026` | Q4 + full year segment revenue |

Note: RKD segments use different names than IBES/press releases (e.g., "Compute & Networking" vs "Data Center"). Compare totals, not individual segment names.

## Known Edge Cases

- **Scaling**: 100% of segment data uses `UnitsConvToCode = 'M'`. No `B`, `T`, or null. Conversion is always x1,000,000.
- **No GBp subunit**: All GBP companies report in GBP (not pence). No subunit conversion needed for segments.
- **Orphan SegIDs**: 29 (Code, SegID) combinations in `qa_RKDFndBGSegData` reference SegIDs not in `qa_RKDFndBGSeg`. 15 companies affected, 4,106 value rows. Filtered in staging via JOIN on `qa_RKDFndBGSeg`.
- **SegOrder→SegID collisions**: 0.02% of rows have multiple SegOrders mapping to same SegID. Deduplicated via `DISTINCT ON` with min SegOrder.
- **Banks**: No "Total Revenue" (item 8). Use "Net Interest Income" (item 14) or "Income Before Tax" (item 32) for validation.
- **Fractional millions**: Small-cap or exotic currency companies have raw values like 3.413M (= 3,413,000 absolute). Precision preserved correctly.

## Regression Values (validated 2026-04-01)

### NVIDIA (USD) — Q4 FY2026, Total Revenue, quarterly

| Segment | Master value | Raw value (M) | Match |
|---|---|---|---|
| Compute & Networking | 61,651,000,000 | 61,651 | ✓ |
| Graphics | 6,476,000,000 | 6,476 | ✓ |
| Consolidated Total | 68,127,000,000 | 68,127 | ✓ |
| **External (press release)** | **$68.1B** | — | **✓** |

### Cosan SA (BRL) — Annual, Total Revenue

| Segment | Master value | Raw value (M) | Match |
|---|---|---|---|
| Raizen Energia | 232,246,624,000 | 232,246.624 | ✓ |
| Cosan Other Business | 3,413,000 | 3.413 | ✓ |
| Eliminations | -10,564,000 | -10.564 | ✓ |

### JPMorgan (USD) — Annual, Net Interest Income

| Segment | Master value | Raw value (M) | Match |
|---|---|---|---|
| Consumer & Community Banking | 58,234,000,000 | 58,234 | ✓ |
| Reconciling Items | -425,000,000 | -425 | ✓ |

### Airports of Thailand (THB) — Annual, Total Revenue

| Segment | Master value | Raw value (M) | Match |
|---|---|---|---|
| Airport business-BKK | 42,258,360,000 | 42,258.36 | ✓ |
| Hotel business | 672,450,000 | 672.45 | ✓ |
