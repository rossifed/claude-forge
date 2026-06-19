# Market-data adjusted prices (FactSet FGP) — Test Fixtures

Source: `master.market_data_adjusted` — full-refresh from FactSet FGP (`fds.fgp_v1_fgp_global_prices`),
adjusted with the golden factors `master.corpact_adjustment` (split/spinoff) + `master.dividend_adjustment`
(dividend). Stores raw + corp-adjusted (`adjusted_*` = Yahoo "Close") + total-return (`tr_*` = Yahoo
"Adj Close") + FactSet pre-computed signals (`return_1d`, `mom_1M/3M/6M/1Y`, `turnover`, `trade_count`).

## Test Panel (split + dividend cases, multi-currency)

| Security | Currency | instrument_id | quote_id | Edge case | External source |
|---|---|---|---|---|---|
| NVIDIA Corp | USD | 38715 | 69191 | Baseline; 10:1 split 2024-06-10; corp==Yahoo Close, tr==Adj Close | finance.yahoo.com NVDA |
| (BRL name) | BRL | 27548 | 49764 | **11 splits + 299 dividends** — richest CA case | — |
| (CAD name) | CAD | 17830 | 33210 | 235 dividends, 1 split | — |
| (CHF name) | CHF | 56725 | 100581 | CHF | — |
| (AUD name) | AUD | 43254 | 77372 | AUD | — |
| (BGN name) | BGN | 68180 | 111558 | **`max_cum_full < 1`** (series ends before last CA event) | — |

(Panel built from: equities with ≥1 corpact split AND ≥6 dividends, one per currency — see query below.)

## Query templates

### Arithmetic correctness (corp/tr == raw × cumulative factor) — must be 0 mismatch
```sql
SELECT quote_id,
  count(*) FILTER (WHERE close IS NOT NULL AND abs(adjusted_close - close*cum_adj_factor)  > 1e-6) AS corp_mismatch,
  count(*) FILTER (WHERE close IS NOT NULL AND abs(tr_close      - close*cum_full_factor) > 1e-6) AS tr_mismatch,
  min(cum_adj_factor) AS min_cum_adj, min(cum_div_factor) AS min_cum_div   -- << 1 on old prices = head OK
FROM master.market_data_adjusted WHERE quote_id IN (<panel>) GROUP BY 1;
```

### Factor recombination (golden vs FactSet's own combined factor) — |diff| ≤ 1e-10
```sql
-- cum_adj_factor × cum_div_factor must equal ∏ div_spl_spin_adj_factor over effective_date > trade_date
-- (validated on NVIDIA K7TPSX-R 2007→2026 and 25 securities USD/BRL/COP/CAD).
```

### Find multi-currency split+dividend candidates
```sql
WITH splits AS (SELECT DISTINCT equity_id FROM master.corpact_adjustment WHERE adj_date > DATE '1900-01-01'),
     divs   AS (SELECT equity_id, count(*) n FROM master.dividend_adjustment WHERE ex_div_date > DATE '1900-01-01' GROUP BY 1 HAVING count(*)>=6)
SELECT DISTINCT ON (cur.code) cur.code, s.equity_id, d.n, q.quote_id
FROM splits s JOIN divs d ON d.equity_id=s.equity_id
JOIN master.quote q ON q.instrument_id=s.equity_id AND q.is_primary AND q.deleted_at IS NULL
JOIN master.currency cur ON cur.currency_id=q.currency_id ORDER BY cur.code, d.n DESC;
```

## Known Edge Cases

- **`div_adj_factor > 1` (9 securities) — DO NOT FIX.** 9 of 898 640 dividend events have a factor > 1
  (max 2.86) — structural events (return-of-capital / special distribution) that FactSet put in
  `div_spl_spin_adj_factor` but not in `adj_factor_combined`, so they don't cancel in the residual
  `div = div_spl_spin / corp`. Effect: `cum_div_factor > 1` → `tr_close > adjusted_close` on ~9 303 rows
  (0.003%). **This is FactSet-faithful** (`cum_full` still == FactSet's combined factor). Clamping
  `div_adj_factor ≤ 1` would BREAK the validated recombination → wrong total return. Leave as-is.
  Find: `SELECT equity_id FROM master.dividend_adjustment WHERE div_adj_factor > 1 AND ex_div_date > DATE '1900-01-01'`.
- **`tr_close ≤ adjusted_close` is the NORM, not a hard invariant.** Total-return-adjusted historical
  prices are scaled down more (dividends) → usually below corp. The 9 securities above are legit exceptions.
- **Head-segment**: prices before an equity's first recorded CA carry the FULL product (incl. the oldest
  event). Verified via a synthetic head row over `[1900-01-01, oldest_event-1]`. Old prices show
  `cum_adj/cum_div` well below 1.
- **`max_cum_full < 1`** for some quotes (e.g. BGN panel): the last priced date precedes the last CA
  event (inactive/delisted series). Not a bug.
- **FGP 2006 floor**: factors and prices start ~2006-01-03; pre-2006 splits visible in Refinitiv prod are
  absent — but there are no pre-2006 FactSet prices to adjust either.
- **`bid`/`ask` = NULL** (FGP supplies neither).
- **`return_1d`, `mom_1M/3M/6M/1Y` = FactSet TOTAL return, calendar period** (from FGP `*_pct`). Copied
  RAW — already CA-adjusted, **never multiply by a factor** (would double-count). `turnover`/`trade_count`
  populated ~70–80% (FactSet sparsity, esp. on `-L`).
- **Coverage ~75%** at quote grain (B1: prefer `-R` consolidated, fall back to `-L`); ~91% on the active
  (non-delisted) universe. The uncovered are mostly delisted shares + warrants/pref/DR.
- **`price_grain` ('R'/'L')**: volume is consolidated for `-R` quotes, single-venue for `-L`.

## Regression Values (validated 2026-06-19, pg-factset-aws-prod)

### NVIDIA (USD, quote 69191 / K7TPSX-R) — around the 10:1 split (2024-06-10) + a dividend ex-date
| trade_date | cum_adj | cum_div | raw close | adjusted_close (corp) | tr_close (total) |
|---|---|---|---|---|---|
| 2024-06-07 | 0.10 | 0.998273 | 1208.88 | 120.89 (= Yahoo "Close") | 120.68 (= Yahoo "Adj Close") |
| 2024-06-10 | 1.00 | 0.998273 | 121.79 | 121.79 | 121.58 |
| 2008-06-16 (dividend head) | 0.025 | 0.915758 | 21.02 | 0.53 | 0.48 |

### Multi-currency arithmetic (12 currencies AED→CLP) — 2026-06-19
All 12 quotes: **0 corp_mismatch, 0 tr_mismatch**. `min cum_adj` 0.11–0.99, `min cum_div` 0.23–0.61
(real splits + dividends, head applied). BRL (49764, 11 splits) → cum_adj 0.30.

### Factor recombination
`cum_adj_factor × cum_div_factor == ∏ div_spl_spin_adj_factor` to **|diff| ≤ 1e-10** (NVIDIA 2007→2026,
+ 25 securities USD/BRL/COP/CAD).
