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

### Primary listing convention CHANGES vs Refinitiv (dual-listed names)

**Verified 2026-07-16 on BlackBerry.** FactSet `is_primary` follows the **home-market**
listing (`fsym_primary_equity_id`/primary listing chain): BB primary = **TSX/CAD**
(adv_66 ≈ 65 M USD). Refinitiv prod flagged the **most-liquid US line**: BB primary =
**NYSE/USD** (adv_66 ≈ 281 M USD). Both masters are internally consistent — screener
AND optimizer each honor their own master's `is_primary` (v1 Refinitiv: both join
`is_primary = true`, same quote guaranteed; v2 FactSet marts: optimizer election puts
`is_primary_quote` first, screener election puts the optimizer's pick first → converge
by construction). But any consumer comparing ACROSS providers sees ×3–4
liquidity/currency jumps on dual-listed names (all Canadian dual-listings, etc.).
**Migration decision needed:** adopt FactSet home-market convention vs custom rule
(most-liquid line) vs preserve Refinitiv continuity. Related liquidity-display trap:
v1 serving exposes `latest_liquidity` = `adv_22`-weekly ("liquidity_adv_20") in
`optimizer.instrument_data` while the screener shows `adv_66` — same quote, different
metric, ~25% apart even when fresh; v2 marts align both on `adv_66`.

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

**Curation pass 2026-07-20/21 — identity-proof rules (learned the hard way, doc §10 of
`legacy-factset-id-mapping.md`):**
- **The continued id = the Refinitiv PRIMARY record** (`adr_primary_mapping` sieve: name-marker for
  ADR, RKD `RelToCode` types 2-7 for dual listings); a secondary/ADR-line id survives only as sole
  handle (unresolved). Secondary lines typed `EQ` slip through any equity_type-based exclusion —
  sieve by the catalogue, not by type. 148 entity + 31 instrument rows were remapped this way.
- **City/postal alone is NEVER an identity proof** — registered-agent addresses and financial-
  district postal clustering confirm across DIFFERENT companies. Identity-grade signals: company-
  owned website domain, phone, street, FactSet former name (≥0.7), identical exchange ticker.
- **For FUNDS, website/phone/street/address are SPONSOR-grade** (all iShares funds share them) —
  fund-level identity proof = **ticker continuity** (survives sponsor renames/repurposings;
  121/121 verified pairs ticker-identical). ETF "repurposing" (new strategy, same vehicle) keeps
  ISIN+ticker → same entity, mapping stays valid.
- **Recycled ISINs between similar-named companies are invisible to name filters** (Allco Finance
  Group → Australian Finance Group share "Finance Group"). Detector: legacy all-delisted-years-ago
  × FactSet entity with an ACTIVE listing → 23 hits/57k seed, 22 same-company, 1 true recycle.
- **Name-translation false negatives are common on non-EN names** (CEMIG: "Energy of Minas Gerais"
  EN vs "Companhia Energética de Minas Gerais" PT; FIBRA sponsor-vs-vehicle names; CRCAM heavy
  abbreviation) — before dropping a large-cap on name discordance, check the ticker.
- **Rows unprovable AND un-researched were deleted, not kept** (411 entity/429 instrument): no
  consumer keyed on them → dropping is free; keeping risks a hidden recycle. Delta companies
  (post-snapshot) must be matched against LIVE `sym_v1_*` symbology, never the frozen June lookups.

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

**Price UNIT — FGP is ABSOLUTE (major currency unit), NO sub-unit scaling (verified 2026-06-19).** Unlike
Refinitiv (which stores minor units — GBp pence, cents — + a `price_unit` divisor, e.g. 0.01), FGP delivers
prices **already in the major unit**. Verified on the classic pence case: BP `4.901` / VOD `1.087` (GBP) in
FGP vs Refinitiv prod `490.05` / `108.7` pence (`price_unit=0.01`) — same value, FGP in pounds. ⇒
`master.market_data_adjusted.price_unit` is a constant **1.0**; **no price scale factor to re-apply**
(distinct from the per-item `unit_factor` for fundamentals/estimates — prices are already normalized).
Migration contract change: UK/sub-unit prices go **pence → major unit (÷100)** vs current prod — same value,
different unit, a visible change for consumers that assumed the pence convention.

### FactSet market cap → master.company_market_cap (+ FX gap)

Source = **`fds.ent_v1_ent_entity_mkt_val`** (grain `factset_entity_id × mv_date`, **133 M rows**). Columns:
`ent_mv` (total market value) + `ent_mv_ex_treasury` / `ent_mv_ex_non_traded` / `ent_mv_ex_non_traded_treasury`
(float-adjusted variants). `currency` = local currency of the value.

**SCALE — never hardcode, JOIN the metadata, and look it up for THE FIELD ACTUALLY USED.** Values are stored
in **MILLIONS**; master stores **absolute**. The factor lives in **`fds.ref_v2_ref_metadata_fields`**
(`table_name='ent_entity_mkt_val'` — no `ent_v1_` prefix — `field_name='ent_mv_ex_treasury'` → `unit_factor`).
Apply `<field> * unit_factor` via a JOIN in **staging** (source-dependent scaling), exactly like
fundamentals/estimates. Verified authoritative and **identical for `ent_mv` and `ent_mv_ex_treasury`**
(checked, not assumed): `unit_factor=1e6`, `cur_indicator=1` (currency value → FX needed for USD),
`split_indicator=null` (no split factor).

**FIELD CHOICE — `ent_mv_ex_treasury`, NOT `ent_mv` (arbitrated 2026-07-27 on the FULL universe; supersedes
the 2026-06-19 `ent_mv` decision).** Per Daily Prices V2 doc p.24, `ent_mv` = market value of **all** share
types (common + preferred + non-traded + **treasury**) → *total entity value*, not a market cap: treasury
shares are nobody's claim. `ex_treasury` removes only treasury (preferred + non-traded stay) = the strict
price × shares-outstanding, i.e. prod's convention. The June decision was **correct but weighted by company
count**; re-measured on 47,473 comparable companies (6,085 discriminating, ±2% vs Refinitiv prod in USD):
- by **company count** `ent_mv` wins 65.4% vs 25.4% (confirms the old ~79%/14% in direction);
- by **dollars** `ex_treasury` wins **×13.6** — 1,010 G$ cumulative absolute error vs 13,692 G$.
Both hold because **Refinitiv's convention correlates with SIZE** (nobody had measured this): mega caps follow
`ex_treasury` (median error 0.0% vs 10.3%), the tail follows `ent_mv` by 0.1%. Top-1000 discriminating (n=322):
ex_treasury 68.9% vs ent_mv 26.1%. **No rank bucket where `ent_mv` costs less in dollars**; crossover ≈ rank
5,000. Zero coverage loss (`ex_treasury` non-null 51,487 vs `ent_mv` 51,480; **0** rows `ent_mv`-only, +7 the
other way). `ent_mv` inflated GE ×3.9, Goldman ×3.2, ExxonMobil ×1.9, JPMorgan ×1.5 → wrong screener default
sort (`latest_market_cap_usd:desc`) and wrong optimizer **sector weights** + small-cap position caps.
Rejected: size-dependent hybrid (rank changes daily → a company would oscillate), loading both columns
(defers the decision). `ent_mv_ex_non_traded_treasury` = the float definition — a different, future decision.
Full method/results: `src/data/docs/factset-migration/validation/market-cap-field-arbitration.md`.
- **VALIDATION TRAP (cost two wrong conclusions):** Apple, NVIDIA, AstraZeneca, HSBC, Samsung have all **4
  variants strictly EQUAL** (zero treasury) → they discriminate NOTHING and will match prod under either
  field. Always include a treasury-heavy name (JPMorgan `ent_mv` 1.32T vs prod 871B = `ex_treasury`).
- **Do NOT read a mega-cap gap as a field regression before checking the DATE** (measured 2026-07-30): dev
  and prod agree at every date to ~0.00004% (Apple 07-29 dev 4,967,117.112 M vs prod 4,967,115 M — residual =
  Refinitiv's rounding to the million). An apparent −0.6% "regression" was dev's J-1 value read from a stale
  ClickHouse mart (`mart_optimizer_v2.company_market_cap_raw` at J-1, `timeseries.*_market_cap` at J-7) while
  prod was queried at J. Compare `valuation_date::text` on both sides FIRST.
- **Open, NOT measured:** why the tail follows `ent_mv`. Hypothesis — on small caps Refinitiv may use *issued*
  shares (treasury included), i.e. **prod itself commits the error there**; reproducing it would not be an
  argument for `ent_mv`. Prod is the incumbent, not the reference for correctness.

**THREE LEVELS NOW LOADED — supersedes the 2026-07-27 "load both columns = rejected" (decided + VALIDATED
2026-08-21).** The single-field arbitration above answered "if you keep ONE column, which?"; the PR
`feat/company-market-cap-3-levels` instead ships **three explicit level columns** on `master.company_market_cap`
because they serve different consumers, so choosing one is the wrong framing:
- `market_cap_ex_treasury` ← `ent_mv_ex_treasury` — the CERTIFIED served convention (screener/optimizer).
- `market_cap_total`       ← `ent_mv` — total entity value; the DEEP backtest/signal series (also the one that
  carries the pre-2015 reconstruction, floor 2006 — see the HISTORY EXTENSION block below).
- `market_cap_float`       ← `ent_mv_ex_non_traded_treasury` — strict FREE FLOAT (ex non-traded AND treasury).
- Legacy `market_cap` is KEPT and **double-fed == `market_cap_ex_treasury`** (same value, free) — a two-phase
  prod-safe rollout (additive migration `0013`, NO rename; serving rewires to ex_treasury, then a later PR
  drops `market_cap`). Scaling: all three carry `unit_factor=1e6`, applied by a metadata JOIN in
  `stg_fds_company_market_cap` (the source rows are in millions). Pre-2015 rows carry `total` ONLY
  (ex_treasury/float NULL there, by design — reconstruction is total-only).
- **INVARIANT `total ≥ ex_treasury ≥ float`** (total adds treasury; float removes non-traded on top of
  treasury). Holds on 134.4M vendor-era rows EXCEPT tiny tails that are **anomalies IN THE FDS SOURCE, not our
  bug** (verified: sampled violations all have the same `ent_mv_ex_treasury < ent_mv_ex_non_traded_treasury`
  in `fds.ent_v1_ent_entity_mkt_val`): 345 rows `total<ext` (0.0003%) + 126,199 rows `ext<float` (0.09%) — most
  are rounding (e.g. 251.468066 vs 251.468070), a few are real provider anomalies (entity `0X82ZG-E`: float 4×
  ext). Golden-source doctrine → we replicate the source faithfully, do NOT silently repair it.
- **VALIDATION vs source (2026-08-21, via MCP on pg-factset):** master == `fds.ent_v1_ent_entity_mkt_val ×
  unit_factor` **to the unit** on NVIDIA (84341: all 3 = 5,317,708,132,935 — mega-cap with zero treasury/
  preferred/non-traded → 3 levels EQUAL is NORMAL, the source itself is equal) and on discriminating names
  (34030: total 393.80G / ext 303.82G / float 152.33G; 35049: total 8× ext) — all exact. Entity resolution =
  `company_id → entity_mapping(data_source_id=2) → external_entity_id = btrim(fds.factset_entity_id)::bpchar`.
- **Perf note (same PR):** the pre-2015 reconstruction `int_company_market_cap_derived_local` was 24.9→5.2 min
  after rewriting its share-match from a range `BETWEEN` (paired each price with the equity's ~966 ranges →
  ~213 G comparisons) to an **AS-OF `LATERAL` join** (`so.date <= trade_date ORDER BY date DESC LIMIT 1`, one
  index-scan per price on `idx_share_outstanding_equity_id_date`) + a `WHERE trade_date < '2020-12-30'` cap
  (nothing ≥2020 is consumed). Whole `etl__market_company_mcap` job 59→39 min. ⚠️ A STALE dbt manifest silently
  recreated the staging VIEW with the OLD (`market_cap`-only) definition and the loader rebuilt master on it —
  after editing staging models, `dbt parse` + reload the code location BEFORE running.

**`shares_outstanding` vs `market_cap` — same basis since the ex_treasury switch, but still APPROXIMATE.**
`fgp_v1_fgp_shares_comp_hist.adj_shares_outstanding` (the only share column, company grain, fiscal-reported,
split-adjusted, ×1e6 via metadata) = shares outstanding **net of treasury** (Toyota 13.03B = its real
outstanding, verified; FactSet has no clean "total/issued" column — total is implicit in `ent_mv`). With
`ex_treasury` both metrics are now net of treasury, so **`market_cap / shares_outstanding` approximates
price** again (it did NOT under `ent_mv`: Toyota +21%, JPM +52%). It stays approximate — mcap still includes
preferred + non-traded classes that the share count excludes, and the two have different grain/frequency
(mcap daily, shares fiscal-quarterly). Do NOT let a consumer recompute price from the two. (Future option:
split mcap & shares into separate master tables, rejoin in serving.)

**REJECTED: computed `primary_close × shares_outstanding`.** Coherent by construction but (a) **~74% coverage
loss** — only ~14.5k companies have a resolvable primary FGP price (`market_data_adjusted`, is_primary, raw
`close`) vs ~51k with `ent_mv` (private/unpriced entities have an entity market value but no traded price);
(b) **share-class mismatch** — applying the primary common price to company-level shares that include
preferred overstates (Samsung +3.9% vs `ent_mv`); (c) fragile primary-equity resolution (JPM = 207
instruments). Use the provider's `ent_mv_ex_treasury` directly.

**HISTORY DEPTH — daily entity mcap starts 2015-12-30 ONLY (whole table, `ent_mv` AND `ent_mv_ex_treasury`
alike); FactSet-only REGRESSES vs prod (verified 2026-07-08).**
`fds.ent_v1_ent_entity_mkt_val` first date = **2015-12-30**, 0 rows before (134 M rows ≈ 10 yr). But current prod
`master.company_market_cap` (Refinitiv-fed, `pg-financial-aws-prod`) goes back to **2000-01-02** — **101 M rows /
43 % of the series live before 2015**. So a FactSet-only daily mcap **drops ~15 yr of history** (misses 2008, dot-com
…) — a real **regression**, not a product choice. Options: **(1) SPLICE (reco to keep daily)** = freeze Refinitiv
daily 2000→2015 + FactSet 2015→ ; coherent because `ent_mv` was chosen to match Refinitiv (~79-85 %) so the 2015
join is near-continuous; needs a one-shot freeze of the Refinitiv history (no live Refinitiv dependency). **(2)**
`ff_v3_ff_basic_der_af/qf`.`ff_mkt_val` = fundamentals-derived mcap back to **1979 (annual) / 1989 (quarterly)** but
LOW-frequency + STRICT price×shares convention (≈ `ent_mv_ex_treasury`, which since 2026-07-27 IS our field →
this option no longer carries a 2015 convention step; the note below revisits it). **(3)** accept 10 yr (hard
to defend vs the 26 yr shipped today). No daily FactSet source older
than 2015 is subscribed (`hlt_*mkt_cap` not loaded; computed price×shares back to 2006 already rejected above).
Decision **TBD** — product/architecture call; a FactSet support ticket asks whether the 2015 floor is a data or a
contractual limit.

**Daily pre-2015 via computed price×shares — VALIDATED but imperfect; SPLICE preferred (2026-07-08).** FactSet
support confirmed the 2015 floor is a **documented DATASET limit, NOT contractual**, and suggested reconstructing
daily mcap from `fp_v2_fp_basic_prices.p_price × fp_v2_fp_basic_shares_hist.p_com_shs_out`, aggregated to entity.
TESTED on the 2015+ overlap — it works, but FactSet's reply **omitted two things**: (a) **symbology level** — fp
is keyed at `-R` (regional), `sym_v1_sym_sec_entity` at `-S` (security) → direct join = **0 rows**; must navigate
`-S → -R` via `sym_v1_sym_coverage.fsym_regional_id`; (b) **scale** — `p_com_shs_out` has `unit_factor=1000`
(stored in thousands). With both fixes, `price × shares×1000` reproduces **`ent_mv` (TOTAL — `p_com_shs_out` is
total incl. treasury, NOT ex_treasury; the earlier "shares net-of-treasury" fear was WRONG for THIS table)**:
median ratio **1.000**; single-security **97 % within ±2 %**; treasury-affected single-security still **82.7 %
within ±2 % vs TOTAL**. BUT multi-security (common+preferred) degrades: **~81 % within ±2 %, a real ~15-25 %
error TAIL on complex/preferred-heavy names** (preferred securities lack fp price/shares → the entity sum
under-counts) — exactly the Toyota/JPM cases behind the original rejection. fp depth: prices & shares to **1984** (shares sparse pre-2000).

**DECISION LEAN (revised 2026-07-09): pure-FactSet reconstruction PREFERRED over the splice.** Freezing Refinitiv
(a provider we're decommissioning) is a strategic dead-end + provenance debt; and a same-method reconstruction is
**methodologically CONTINUOUS** with the 2015+ `ent_mv` (no convention jump at 2015 — which the SPLICE *does*
introduce for the ~15-21 % of names where Refinitiv ≠ `ent_mv`). The blocker = the **~15-25 % multi-class tail**
(big/preferred names understated because fp_basic `p_com_shs_out` is common-only). It is likely reducible — the
preferred/non-traded classes simply aren't in fp_basic. **OPEN: FactSet ticket asks where the preferred/non-traded
share classes live (price+shares), or for a security-level breakdown of `ent_mv` extendable pre-2015.** If the tail
closes → pure-FactSet reconstruction; **SPLICE = fallback** only if it proves irreducible. Fixing the regression
itself (shipping 10 yr vs prod's 26) is non-negotiable. Validation queries + accuracy profile: this session.

**⚠️ The 2026-07-27 `ent_mv` → `ent_mv_ex_treasury` switch INVALIDATES the premise of the two paragraphs above —
the pre-2015 lean must be RE-EXAMINED (not re-measured yet).** All three options were scored against a TOTAL
`ent_mv` target; the 2015+ series is now ex-treasury:
- **fp reconstruction** (`p_price × p_com_shs_out`) reproduces **TOTAL** (`p_com_shs_out` includes treasury) →
  it no longer joins continuously at 2015; a treasury deduction pre-2015 would be needed, and FactSet ships no
  historical treasury-share count that we've located. Its claimed advantage (methodological continuity) is gone.
- **`ff_mkt_val`** (option 2) is the strict price × shares-outstanding, i.e. ≈ our new convention → the "2015
  convention step" objection against it FALLS. Cost is unchanged: annual/quarterly, not daily.
- **SPLICE** — the Refinitiv side is what `ex_treasury` was chosen to reproduce at the top of the universe
  (0.0% median error there), so the 2015 join is *more* continuous for mega caps than under `ent_mv`, and
  *less* continuous for the tail (which followed `ent_mv` by 0.1%).
Nothing above is measured on the new field; treat it as the re-scoring to run, not as a conclusion. The
`≈ ent_mv_ex_treasury` equality for `ff_mkt_val` is a carried-forward claim from 2026-07-08, never verified
row-level.

**HISTORY EXTENSION — DECIDED + fp reconstruction MEASURED/VALIDATED (2026-08-18). Supersedes the "re-scoring
to run" above for the daily path.** Full analysis + queries: `src/data/docs/factset-migration/validation/
market-cap-history-extension.md`.
- **Architecture = separate series, each continuous where it exists** (NOT one spliced column — a single column
  would put a convention break at 2015 on treasury-heavy names). **`total`** = fp reconstruction (deep) +
  `ent_mv` total (2015+), the backtest/signal series; **`ex_treasury`** = the served convention, `ent_v1`
  2015+ only, no pre-2015 overlay; **`float`** = `ent_mv_ex_non_traded`, 2015+ only (optional add). This
  **dissolves** the "treasury-deduction pre-2015 / discontinuity at 2015" problem above: total stays total
  throughout, ex_treasury is a *different served field*, so there is no convention step to reconcile.
- **Product decisions:** pre-2015 ambition = **total daily only**; floor = **2000** (restore prod parity).
- **fp reconstruction recipe (VALIDATED):** per entity, take the **primary equity** `-R` only
  (`sym_coverage.fsym_primary_equity_id` → its `fsym_regional_id`), `p_price` × (last `p_com_shs_out` ≤ D) ×
  1000. TWO mandatory guards found the hard way: (1) **exclude ADR/DR/GDR/NVDR** — an entity carries many `-R`
  (ADR + DR + foreign listings, mixed currencies); summing them gives ratios in the *billions*. (2) **one `-R`
  per entity** (the primary), because the same share class lists in several regions (AstraZeneca: 2 SHARE `-R`
  London+US = same shares) → summing double-counts.
- **Measured (ratio recon/`ent_mv` total):** 5 names / 3 ccy all **1.0000** (Toyota JPY, AstraZeneca/HSBC/Shell
  GBP, TotalEnergies EUR).
- **UK pence trap RULED OUT:** `fp_v2_fp_basic_prices` is in **major currency unit (pounds, not pence)** — like
  FGP; AZN 114.6 / HSBC 15.28 / Shell 33.2 reconcile exactly. No sub-unit scaling.
- **SPLIT-SAFE (resolves the long-open split-adjustment question for mcap):** `fp_basic` ships **price AND
  shares point-in-time / as-reported (UNADJUSTED)**. Verified on NVIDIA 10:1 (eff. 2024-06-10): pre = $1224 ×
  2.46B, post = $122 × 24.6B, ratio **1.0000 on BOTH sides**, mcap continuous ~$3T. The feared "adjusted price
  × raw shares" mismatch does NOT occur; no split factor to re-apply. Dividends are a non-issue for mcap.
- **Coverage vs our master (proxy: any primary `-R` with a `shares_hist` record ≤ D; prices are dense):**
  by **2000 = 37,590** companies, by 2006 = 53,267, by 2010 = 66,121, by 2014 = 76,490 (vs 65,159 served today
  at 2015+). Floor 2000 feasible; counts exceed today at 2006+ because they include **since-delisted** companies
  → **survivorship-bias-free**, ideal for backtest.
- **Only open item (known, accepted):** the **multi-class tail** — the primary-equity recipe under-counts
  genuine dual-class names (common + a distinct preferred/B-class: Samsung, VW-pref, …) by the value of the
  non-primary class; magnitude on our names not yet quantified. `ex_treasury`/`float` served path is unaffected
  (2015+ `ent_v1`, exact).
- **Query-perf gotcha:** `fp.fsym_id`/`ent_mv.factset_entity_id` are `bpchar`; comparing to a `text` value (e.g.
  from `VALUES`) disables the PK index → 1B/135M-row seqscan (this, not IO, was the "saturation"). Cast the key
  `::bpchar`; `btrim(<indexed col>)=…` also kills the index. Concurrent `sym_*` referential loads slow
  symbology queries specifically (verified: `INSERT`/`ANALYZE` on `sym_coverage`, **0 blocked locks**).

**Entity resolution:** `ent_mv.factset_entity_id` (char, btrim) = `entity_mapping.external_entity_id`
(data_source_id=2) → `internal_entity_id` = entity = company (`company_id` = `entity_id`, inheritance).
Intermediate resolves currency → `currency_id`.

**FX — RESOLVED (2026-07-07): FactSet now ships an FX table.** Since `cur_indicator=1` (mcap in local
currency), USD conversion (`company_market_cap_usd`) needs an FX source. The earlier gap is closed —
FactSet added **`fds.ref_v2_econ_fx_rates_usd`** (⚠️ real name carries the `econ_` infix, NOT the earlier
guessed `ref_v2_fx_rates_usd`). Verified on `pg-factset-aws-prod`: 636 770 rows, **77 currencies**,
1970-01-30 → 2026-07-05 (fresh, J-2). Grain = `iso_currency × exch_date` (daily spot). Two directions:
`exch_rate_usd` (USD value of 1 local unit, e.g. EUR→1.1415) and `exch_rate_per_usd` (local per 1 USD,
JPY→162.34). Metadata companion `fds.ref_v2_iso_currency_map` (currency-code validation). No dedicated
cross-rate table (`ref_v2_fx_rates` still absent) — derive crosses by USD triangulation.

**Coverage vs real demand (currencies actually in `ent_v1_ent_entity_mkt_val`):** 72 currencies demanded,
**66 covered incl. USD-base (91.7 %), 6 MISSING** = `TND, ZWG, VES, ZMW, IQD, BMD`. All 6 are a frontier
tail but **NOT out-of-perimeter**: they resolve into `master.company` and every one is quoted →
**188 real quoted companies** would get `company_market_cap_usd = NULL` untreated (TND=80 is 43 % of the
tail; only 3 of 83 TND entities fail to resolve). Lesson: don't hand-wave a tail as "probably negligible" —
measured, it's 188 live quoted companies, ~0.4 % of the ~50 k universe.

**Refinitiv (prod `master.fx_rate`, still fed) covers ALL 6 as a fallback** (verified 2026-07-07): VES 46 456,
ZMW 41 488, TND 41 178, BMD 38 985, IQD 34 673, ZWG 24 113 rows, all fresh to 2026-07-05. (⚠️ Refinitiv ZWG
starts 2009 though "Zimbabwe Gold" is an Apr-2024 unit — code reused for an earlier ZW currency; irrelevant
for current mcap, only today's rate matters.) ⇒ the gap is fully closeable without a new external source.

**Decision (2026-07-08): ACCEPT the gap, NO per-currency band-aid — KNOWN LIMITATION, real fix deferred.**
Verified post-load on the FactSet master (latest date): **171 quoted companies across the 6 currencies drop
out of `master.company_market_cap_usd`** — TND 72, ZWG 36, VES 28, ZMW 18, IQD 10, BMD 7. Real examples:
Banque Internationale Arabe de Tunisie / Poulina Group (TND), Econet Wireless Zimbabwe / Delta Corp (ZWG),
Banco Provincial / Mercantil (VES), Asiacell / National Bank of Iraq (IQD), LOM Financial (BMD). ⚠️ The view
uses an **INNER JOIN** on `fx_rate`, so these rows **vanish entirely (not NULL)** → invisible to the screener /
optimizer size ranking, silently.

**No sparadra:** we do NOT peg BMD=1.0 and do NOT rebranch Refinitiv FX — a per-currency hardcode is a
band-aid, not a strategy. We ACCEPT the missing USD market cap for these ~171 frontier companies FOR NOW
(~0.35 % of the ~50 k universe; VES/ZWG USD values would be hyperinflation noise anyway). The real fix is a
deliberate **FX-fallback strategy**, TBD: either a broader FactSet FX entitlement (the econ table currently
ships only 77 currencies) or a dedicated secondary FX feed (ECB/IMF/Refinitiv) wired as an explicit
multi-source FX layer decoupled from the primary FactSet spine. **Open design point (independent of the
source fix):** switching `company_market_cap_usd` to a **LEFT JOIN** would keep these companies visible with
`market_cap_usd = NULL` instead of silently dropping them — a correctness improvement to fold into the real
solution. Ingestion contract: `master.fx_rate` built from `ref_v2_econ_fx_rates_usd` (+ injected USD=1.0
numeraire row — the source has no USD line, without it zero X→USD pairs are produced), triangulated to the
full N×N cross matrix + identity in `int_fx_rate`, loaded in-place (`TruncateInsertConfig`, identity-preserving
so the dependent `company_market_cap_usd` view survives).

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
`currency` on `ff_*` = trading currency (AMBIGUOUS vs filing ccy — verify). FactSet FX now available:
`fds.ref_v2_econ_fx_rates_usd` (see market-cap FX section for coverage/decision).

### Classification framework — multi-scheme (GICS + FactSet Sector + RBICS)

Classifications are **multi-scheme**: parallel lenses on the same entities via `classification_scheme/
level/node` + `entity_classification(entity_id, scheme_id, node_code)`. **Assignment is at the ENTITY
grain, no subtype filter** — companies, funds, any type FactSet classifies flow through; filtering
(e.g. excluding funds) is a downstream/consumption concern. Adding a scheme = seed row (id+mnemonic) +
2 staging models (`stg_fds_<scheme>_classification` tree + `stg_fds_<scheme>_entity_mapping` assignment)
+ a UNION branch in the `int_classification_*`/`int_entity_classification` models. 3 schemes live
(scheme_id GICS=1, FactSet Sector=2, RBICS=3; SIC=4/NAICS=5 reserved; themes=101+ deferred). Full doc:
`src/data/docs/factset-migration/A-referential/classification/classification-framework.md`.

- **FactSet Sector** (scheme 2): FactSet proprietary, 2 levels (22 sectors→138 industries), provider-
  native/refreshable from `ref_v2_factset_sector_map`/`_industry_map` + `sym_v1_sym_entity_sector`.
  **99.7% coverage (139,015 = companies + funds)** → fills the GICS gap. Drop the `9999` "Not Classified"
  sentinel (collides across both levels). Funds land in "Miscellaneous / Investment Trusts/Mutual Funds".
- **RBICS** (scheme 3): FactSet Revere, revenue-based, **6 levels** (Economy→Sector→Sub-Sector→Industry
  Group→Industry→Sub-Industry = 14/37/111/385/971/2021 = 3,539 nodes) from `rbics_v1_rbics_structure`
  (current = `end_date IS NULL`; codes are prefix-hierarchical 2/4/6/8/10/12 digits). Entity assignment
  at **L2 focus** (`sym_v1_sym_entity_sector_rbics`, 1/entity); granular L6 revenue segments
  (`rbics_bus_seg_*`, multi-membership) = deferred. 130,269 coverage.
- **When to use**: GICS = investment standard/comparability; FactSet Sector = coverage; RBICS = granular/
  thematic (what a company sells). NACE/CIC = code maps only (no entity assignment), unusable.

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

### Workbench themes — NOT master-eligible; serving-composed (decided 2026-07-20)

Prod carries 13 thematic classification schemes (ids 101–114) alongside GICS in the generic
framework. Verified provenance: scheme_id = workbench theme id + 100 (`raw.wb_themes` ids 1–14),
and node codes are SYNTHESIZED name-hashes (`L1_APPLICAT_1ddf`) because the workbench export
(`wb_theme_instruments`) ships only name paths (level_1..level_8 per ISIN), no stable node ids.
⇒ identity is workbench-owned and rename-fragile (rename → new code → silent assignment churn).
Source-contract test FAILS in practice → themes do NOT enter the FactSet master. Serving
composes theme trees + assignments (ISIN → entity_id at build). Promotable later only if the
workbench ships stable scheme/node ids. Side effect: no theme ids in master → the 101+ margin
question vs FactSet Sector (2) / RBICS (3) is moot.

**GICS custom nodes trap:** prod GICS = 275 nodes = 273 official + workbench grafts (confirmed
`451099` "Digital Assets"; FactSet seed = exactly 273). Bootstrap validation will EXCLUDE
companies assigned to custom nodes — decide add-to-seed vs remap-to-parent before load.

### FactSet total return — fp_v2 product exists; QA reference only, master TR stays derived

`fds.fp_v2_fp_total_returns_daily`: 201 M rows, 1985 → J-2, grain fsym_id × p_date,
`one_day_pct` (daily return %, not an index level). Decision: NOT materialized in master —
master/serving TR = derived from market_data + dividend_adjustment (already validated by
recomposition against precisely this table). Keep fp_v2 as QA cross-check only; two TR truths
(fp source vs FGP derivation) would diverge at the margin. **DONE (2026-07-22):** the derived TR
is LIVE — `master.market_data_adjusted` exposes `total_return_*` (price × cum_full_factor,
row-wise); CH `market_metrics` recomputes `tr_close` the same way. The `master.total_return`
table + its loader + the QA feed (`DS2PrimQtRI`, int/stg_qa_total_return_*) were REMOVED from dev
code (empty 0-row tables linger on pg-factset until the next schema replay drops them).

### FactSet migration — retired prod tables (decided 2026-07-20, IMPLEMENTED on dev 2026-07-22)

- `company_weblink` (396 k, Refinitiv RKDFndCmpWebLink): OBSOLETE — FactSet ships a single
  website; expose on `company`, no table. **DONE — table + weblink_type + API/serving/loaders removed.**
- `adr_primary_mapping`: OBSOLETE — FactSet single-entity model. (Refinitiv-only concept; retirement decided.)
- `total_return` table: replaced by derived view (see above). **DONE — removed from dev code.**
- `estimate_segment*`: not in FactSet feed (entitlement) — accepted gap. **DONE (empty-by-schema):** the
  4 tables are KEPT (SQLAlchemy + Alembic) but left EMPTY — all feeds removed (loaders + int_estimate_segment*
  + stg_qa_estimate_segment_* + stg_qa_estimates_mapping). Research reads the empty tables and its
  investment-case tool falls back to RKD **financial** segments (`financial_segment_value`, FactSet-fed) —
  `tool_builder.segment_revenue_analysis_df` = `_try_sources([IBES 8/9, RKD 1/2])` returns the first
  non-empty. With this, the WHOLE remaining QA ingestion was removed: **zero `stg_qa`/`qa_*` on the
  FactSet dev path** (only historical code comments name old stg_qa for lineage).
- `macro_*` (FRED): out of migration scope, unchanged, already out of the daily job.
- KG family (kg_triplet, supply_chain, competitor, long_term_risk, hidden_connection,
  entity_concept) + `gics_company_classification`/`last_metrics` read-models → serving.
- ⚠️ stray `master.entity_financial_ratio` snapshot in pg-factset (830 452 rows, 2026-06-25,
  14 908 entities, compute experiment) → purge; ratios belong to CH `signals`.

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

### FactSet fund instruments — exchange-traded fund shares ARE master equities (decided 2026-07-09)

`master.fund` covers fund ENTITIES only (27,888 loaded: ETF 27,743 / OEF 144 / CEF 1) — **zero
instruments/quotes** (verified 0/27,888). The equity chain excludes funds twice by construction:
scope = `stg_fds_company` (fund entities never enter) AND the `stg_fds_equity_coverage` whitelist
(`universe_type='EQ'` + `fref_security_type IN (SHARE, PREF, …)` — comment says "funds/ETF out of
scope here"). FactSet side is complete (e.g. Virtus BBC ETF `04J5F9-E`: 1 `-S` `ETF_ETF`, 2 `-R`,
~34 `-L`, FGP prices, 14 `DVC` dividends in `fgp_v1_fgp_ca_events`).

**Decision — fund shares feed `master.equity` (LOADED 2026-07-09).** ALL fund share classes
(`ETF_ETF`, `MF_C`, **and `MF_O`**) → `instrument` (type `EQU`) + `equity` (`equity_type` adapted
1:1); quotes ONLY for venue-traded types (`ETF_ETF`/`MF_C` — MF_O "listings" are NAV-publication
pseudo-venues: Morningstar `MST*`, `ZZ*`; 0/2,052 in FGP). Entity = `fund`. Rationale: (1)
**structural (decisive)** — the whole CA/adjustment chain (`dividend`, `corpact_*`, `*_adjustment`,
`share_outstanding`) is FK'd on `equity_id`; no equity row = no adjusted prices / total return, and
ETFs have real FGP CA events; MF_O too (fp_v2 dividends/splits); (2) **prod continuity** —
Refinitiv prod already stores listed funds in `equity` (`ET` 700 / `CF` 854 / `INVT` 314 / `ETC`
18); (3) FactSet tags ALL fund securities `universe_type='EQ'`. The company-vs-fund ontology lives
at ENTITY level (`company`|`fund`), never at instrument level. Rejected: entity-level split
(recreates the Refinitiv ADR defect); dedicated instrument type without equity row (forks the
adjustment chain). `FND` instrument_type = unused reserve.

- **Architecture (SOLID, per-layer perimeters):** scope registry (`stg_fds_instrument_scope` =
  UNION of per-class `stg_fds_scope_*` — the activation switch) + 2 seeds: `instrument_class_
  security_types` (owned by instrument chain; also drives the equity_type catalog whitelist) and
  `quote_security_types` (owned by quote chain; presence = quoted; NO MF_O row). Mechanics
  (coverage/equity/quote/int) are class-agnostic and CLOSED — adding an entity class touches no
  existing model. Layering is hard: instrument materialization has ZERO quote knowledge.
- **Loaded (pg-factset-aws-prod):** 27,526 fund instruments+equities (23,475 ETF / 23 MF_C /
  4,156 MF_O — extinct funds NOT in scope yet), 54,411 fund quotes (0 MF_O), 19,219 funds served.
- **Equivalence-proof pitfall:** `fds.*` moves daily → never fingerprint-compare a rebuild against
  yesterday's tables; replay the OLD SQL on the CURRENT source vs the new build, same snapshot.
- **Ops:** dbt full-refresh of a staging table CASCADE-drops dependent views (int_equity/int_quote/
  stg_fds_exchange/int_venue) — rebuild them; venue catalog derives from stg_fds_quote → after a
  quote-perimeter extension run dbt → `venues` asset → `quotes` asset (else quotes drop on
  unresolved venues; 5,993 recovered this way).
- Excluded entirely: `ETF_UVI`/`ETF_NAV` (synthetic NAV series), `STRUCT`/`TEMP`/`RIGHT` (junk),
  non-fund-share tails held by fund entities (DR/WARRANT/SHARE).

## Known Pitfalls

### `is_major_security` — propriété de société, PAS de négociabilité (mesuré 2026-07-27)

Dérivé de `sym_v1_sym_coverage.fsym_primary_equity_id` (identité FactSet) filtré par le seed
`instrument_class_security_types.csv`. **Aucune dimension de vie/mort** : la liveness vit dans
`master.equity.delisted_date` (posé ssi `active_flag=0`). Les deux sont orthogonaux.

- **Exactement 1 major par société, vivante ou morte** : 119 485 majors / 123 937 entités, dont
  76 879 cotés et 42 606 délistés — et **0 société n'a les deux**. Une société liquidée garde donc
  son major. Normal, pas une dérive.
- **0 major sur ADR/DR/GDR/NVDR/PREF/PREFEQ** (vérifié sur les 215 252 titres, exhaustif). Garanti
  par NOTRE seed, pas par le provider → une ligne ajoutée au CSV casse l'invariant en silence.
- **PIÈGE : classer sur `is_major_security` sans filtrer les délistés renvoie des sociétés mortes.**
  Cas `TSM` : les 2 seuls majors du symbole sont Tasman Metals (mort 2016) et Tien Son Cement
  (2015) ; TSMC n'a que des ADR/DR (non-major), sa major est la ligne taïwanaise `2330`.
  Le flag est *muet*, pas faux, quand la major de la société est hors du sous-ensemble interrogé.
- 47 % des equities de `serving` sont délistées (101 372/215 252) et restent candidates à
  `/api/data/instruments_data/resolve/`, qui n'applique aucun filtre de vie. Gate ⇒ symboles
  ambigus 14 724 → 8 532.
- Analyse complète : `src/data/docs/factset-migration/A-referential/equity/major-security-semantics.md`

### ADR companies — Refinitiv models a company-with-ADR as TWO companies

Refinitiv QA models a company that has an ADR as 2 distinct `master.company` rows:
the ordinary line (primary) + a separate ADR line (name marker `'- ADR'` / `'(ADR)'`).
The optimizer needs both folded onto one logical company. 1058 name-matched ADR
pairs exist (1003 distinct ADR; total 1763 ADR-tagged companies).

- **`master.company.primary_company_id` is NOT reliable for this**: NULL in ~90% of
  ALL companies, and on the 1058 ADR pairs it links correctly only 915× (86.5%) —
  86 NULL (e.g. Alibaba), 57 wrong. Do not use it as the ADR→primary mechanism.
- **`organization_id` is a Refinitiv OrgID — a SEPARATE id space, NOT a `company_id`**
  (max ~128M vs `company_id` max ~140k). NEVER join `organization_id = company_id`
  (~39k coincidental value matches = pure noise). Use it ONLY as a self-join
  (`company A.org = company B.org`) to group peers. It corroborates the exact name
  match at 98.2% but contradicts 15× (Refinitiv org collisions / spin-offs, e.g.
  Metso→Neles, Amersham→American Home Mortgage) — so it must **NEVER override an
  exact name match**. `ultimate_organization_id` is NULL across the ADR perimeter
  (unusable).
- **Solution: `master.adr_primary_mapping`** (dbt model `models/master/`, view over
  `master.entity`+`master.company`). Resolves `adr_company_id → primary_company_id`
  by EXACT unique name match (UPPER/TRIM), with a human-curated override seed
  (`seeds/adr_primary_mapping_override.csv`, schema `seed`) applied at top priority
  for the 53 ambiguous-name cases (ADR name matches >1 company, e.g. ABB Ltd vs a
  duplicate Abb Ltd; override pick = the candidate that is org-self-referencing).
  Contains all 1763 ADR (1 row each) so it doubles as the exhaustive ADR catalogue.
  Coverage: **1003/1763 resolved** (53 override + 950 name); 760 `unresolved` = ADR
  whose ordinary line is simply not loaded in `master.company` (e.g. many Chinese
  ADRs: 17 Education, 51job, 36Kr) — fold as standalone, nothing to link to.
- **Quick-win / band-aid** pending the FactSet migration, which changes the entity
  model (ADR + ordinary expected to collapse to one entity).

### Country fields in master — 3 semantics; screener geography = LISTING country (ADR trap)

Master carries country in 4 tables with DIFFERENT semantics (FactSet feed, verified
2026-07-17 on pg-factset-aws-prod):
- `company.country_id` = **company domicile/HQ** (`ent_v1_ent_entity_coverage.iso_country`;
  Alibaba → CN. n=1 check suggests HQ not incorporation — CN despite Cayman inc.; unverified
  on redomiciliations/inversions).
- `equity.country_id` = **listing region of the SECURITY**, NOT issuer country: the
  ticker-region suffix (`stg_fds_equity_ticker`: `split_part(sym_v1_sym_ticker_region
  .ticker_region,'-',2)`, e.g. `BABA-US` → US).
- `venue.country_id` = exchange country; `fund.country_id` = fund domicile.
- `quote` has NO country — inherits via `venue`.
⇒ one security can carry 3 distinct countries: company (CN), equity (US), venue (US).

**Screener exposes the EQUITY (listing) country as `iso_country`** — both dbt v1
(`src/screener/.../models/screener/instrument.sql`, join on `e.country_id`) and CH mart v2
(`src/screener/pipelines/mart_assets.py`, join `country_reference_raw.code_alpha2 =
equity.country_code`). The API geography filter (`iso_country__eq/in/notin/like`) therefore
filters on WHERE THE LINE TRADES. Measured: **91 % of ADR (5,409/5,925) carry US** while the
company domicile is GB 574 / CN 567 / JP 520 / AU 423 / HK 346 / … (only 123 truly US); 446
ADR have NULL equity country (no ticker_region). Consequences: geography=US surfaces ~5.8k
foreign-company ADRs; Alibaba's ADR never appears under China. Verified example — Alibaba
(company CN): ADR `BABA`→US, HK share→HK, DR `BABA34`→BR, DRs→AR/TH/SG (each = its venue).

**Provider dimension — part of this is Refinitiv-inherited and CHANGES with the FactSet
migration.** Under Refinitiv, the problem is compounded by the two-company ADR modeling (see
"ADR companies — Refinitiv models a company-with-ADR as TWO companies" above): the ADR is a
SEPARATE `master.company`, so even the company-level domicile is polluted (the ADR line has no
clean link to its ordinary's home country) — geography anomalies there are partly a PROVIDER
MODELING artifact, not just a field-choice issue. FactSet collapses ADR + ordinary onto ONE
entity: `company.country_id` is the clean home domicile (Alibaba CN) and the ADR is just one
more security under it. ⇒ after migration the *company-duplication* half of the problem
disappears, but the *field-choice* half PERSISTS (all numbers above are measured on the
FactSet master): the screener still reads `equity.country_id` = listing country, so ADRs
still surface under US. Do not assume Refinitiv-era ADR/geography symptoms and FactSet-era
ones are the same bug — same visible symptom, different root causes and different fixes.
(Refinitiv `equity.country_id` lineage — `DSCtryQtInfo` quote-country — is also listing-ish,
but its exact semantics were never verified to the same depth; unmeasured.)

Code smells in the v2 mart (`mart_assets.py`): alias `issuer_country` is a **misnomer**
(it is the ticker-region/listing country), and a second `country` join on `venue.country_id`
is dead code (never selected). Reco (NOT implemented): expose BOTH `listing_country` and
`company_country` (from `company.country_id`, already in master) and point the geography
filter at the company country; the delta only shows on ADR/DR/cross-listings — a fix that
only becomes clean POST-migration (FactSet single-entity model); under Refinitiv the ADR
"company" has no reliable home-country to point to.

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

### Split adjustment — problème transverse estimé/fondamentaux (chantier différé, mesuré 2026-08-13)

Les valeurs FactSet PAR ACTION sont livrées split-ajustées as-of `adjdate` (colonne présente sur
`fe_v4_fe_basic_conh_lt`/`conh_rec` et `ff_*`), mais **ni `adjdate` ni un facteur de split ne sont
conservés dans master** → la valeur brute point-in-time est irrécupérable. Impact = **look-ahead en
backtest** dès qu'on mélange une valeur par-action ajustée avec une base différente (cas phare : prix
cible ajusté vs prix brut d'époque, pour l'upside). Mesuré sur PRICE_TGT : **~36 % des lignes ont
`adjdate` > `effective_date`** (donc ré-ajustées rétroactivement pour des splits postérieurs au snapshot).
NB : les comparaisons **même-source** (P/E = prix ajusté / EPS ajusté) restent correctes — le split
s'annule ; seul le **mélange de bases** casse.

- **Périmètre impacté (famille « par-action ») :** `estimate_consensus` (EPS…), `estimate_non_periodic`
  (PRICE_TGT/RNAVPS ; pas EPS_LTG qui est un %), `estimate_actual` (EPS réalisé, DPS…),
  `std_financial_value` (sous-ensemble EPS/DPS/BVPS/FCF-per-share + comptages d'actions). **NON impactés :**
  le reste de `std_financial_value` (montants absolus), les revenue segments (`financial_segment_value`,
  absolus), `estimate_recommendation` (notes), le market cap (absolu).
- **Colonne `split_factor` :** exposée et **toujours NULL** sur `estimate_consensus` +
  `estimate_non_periodic`, **absente** sur `estimate_actual`/`std_financial_value`. Décision 2026-08-13 :
  **on ne touche pas au schéma** — la garder (cohérence avec les tables où elle existe déjà) ; elle ne
  portera de l'info qu'une fois le chantier livré. Ne PAS s'appuyer dessus tant qu'elle est NULL.
- **Le facteur N'EST PAS dans les tables d'estimé** (seulement `adjdate`, une date) → il faut le récupérer
  ailleurs et le **cumuler sur (effective_date → adjdate]**. L'ancrage diffère de celui des prix (cumul
  prix ancré sur aujourd'hui).
- **Source de split à réutiliser = famille FGP déjà employée pour les prix**, PAS `fp_v2_fp_basic_splits`
  (produit FP non utilisé chez nous) ni le `cum_full_factor` total-return (dividende inclus + ancré
  aujourd'hui). Vérifié : `master.corpact_adjustment` ← `fgp_v1_fgp_ca_adj_factors.adj_factor_combined`
  (splits+spinoffs, dividende exclu) ; `stg_fds_corpact_event` ← `fgp_v1_fgp_ca_events`. Motif DRY : une
  seule vérité de split partagée prix + estimé, sinon divergence cross-source pile sur l'upside.
- **Pourquoi deux tables de split chez FactSet :** ce sont **deux produits de prix** — FGP (Global Prices,
  consolidé, notre feed → `fgp_v1_fgp_ca_*`) et FP basic (IDC, non utilisé → `fp_v2_fp_basic_splits`).
  L'événement réel est le même ; FactSet livre les CA par ligne de produit.
- **Cible = même standard que market_data :** garder la valeur brute + un facteur split ré-appliquable
  (comme `market_data` garde le close brut + le facteur), pour servir au choix la version ajustée ou la
  version point-in-time.
- **OUVERT (à trancher dans le chantier, NON vérifié) :** FactSet ajuste-t-il l'estimé **splits-seuls**
  ou **splits+spinoffs** ? → décide `corpact_adjustment` (split+spinoff) vs `fp_v2_fp_basic_splits` (split
  pur). Se vérifie sur un cas de spinoff réel (valeur estimée avant/après vs facteur de chaque table).

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
