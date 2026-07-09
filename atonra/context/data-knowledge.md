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

**SCALE — never hardcode, JOIN the metadata.** `ent_mv` is stored in **MILLIONS**; master stores **absolute**.
The factor lives in **`fds.ref_v2_ref_metadata_fields`** (`table_name='ent_entity_mkt_val'` — no `ent_v1_`
prefix — `field_name='ent_mv'` → `unit_factor`). Apply `ent_mv * unit_factor` via a JOIN in **staging**
(source-dependent scaling), exactly like fundamentals/estimates. Verified authoritative: `unit_factor=1e6`,
`cur_indicator=1` (currency value → FX needed for USD), `split_indicator=null` (no split factor).

**FIELD CHOICE — `ent_mv` (TOTAL), NOT `ex_treasury` (verified 2026-06-19, random n=500 + treasury-affected
n=100 vs Refinitiv prod).** Per Daily Prices V2 doc p.24, `ent_mv` = market value of **all** share types
(common + preferred + non-traded + **treasury**) → it is *total entity value*, NOT textbook float market cap.
Prod matches **`ent_mv` ~79%** of treasury-affected names (85% of ALL companies within ±2%), `ex_treasury`
~14%, **neither** ~7% — **Refinitiv mixes conventions per company; no single FactSet field reproduces it.**
Chose `ent_mv` for prod-continuity + zero rework (picking `ex_treasury` would visibly change ~22% of
companies, e.g. Toyota −17.5%; Samsung would instead *rise* +3.9% — direction is structure-dependent, NOT
uniform). `ent_mv_ex_treasury` ≡ `ff_mkt_val` = the strict (price × shares-outstanding) market cap — **defer
as a future SEPARATE column** if the strict definition is ever needed (`ff_mkt_val` itself unusable as a
source: `ff_basic_cf` is a snapshot, 1 row/fsym, no history). **LESSON: the earlier "cross-checked to the
digit" note (AstraZeneca/HSBC/Samsung) was incomplete — those are zero-treasury names where `ent_mv ==
ex_treasury`; a treasury-heavy name (JPMorgan: `ent_mv` 1.32T vs prod 871B = `ex_treasury`) is what exposed
the variant question. Always include a treasury/preferred-heavy sample.**

**`shares_outstanding` is NOT reconcilable with `market_cap` — independent metrics by design.**
`fgp_v1_fgp_shares_comp_hist.adj_shares_outstanding` (the only share column, company grain, fiscal-reported,
split-adjusted, ×1e6 via metadata) = shares outstanding **net of treasury** (Toyota 13.03B = its real
outstanding, verified; FactSet has no clean "total/issued" column — total is implicit in `ent_mv`). Because
`ent_mv` counts treasury but shares is net-of-treasury, **`market_cap / shares_outstanding ≠ price`** for
treasury/preferred-heavy names (Toyota +21%, JPM +52%). Stored as independent metrics; do NOT expect a
consumer to recompute price from the two. (Future option: split mcap & shares into separate master tables,
rejoin in serving — different grain/source/frequency: mcap daily, shares fiscal-quarterly.)

**REJECTED: computed `primary_close × shares_outstanding`.** Coherent by construction but (a) **~74% coverage
loss** — only ~14.5k companies have a resolvable primary FGP price (`market_data_adjusted`, is_primary, raw
`close`) vs ~51k with `ent_mv` (private/unpriced entities have an entity market value but no traded price);
(b) **share-class mismatch** — applying the primary common price to company-level shares that include
preferred overstates (Samsung +3.9% vs `ent_mv`); (c) fragile primary-equity resolution (JPM = 207
instruments). Use the provider's `ent_mv` directly.

**HISTORY DEPTH — daily `ent_mv` starts 2015-12-30 ONLY; FactSet-only REGRESSES vs prod (verified 2026-07-08).**
`fds.ent_v1_ent_entity_mkt_val` first date = **2015-12-30**, 0 rows before (134 M rows ≈ 10 yr). But current prod
`master.company_market_cap` (Refinitiv-fed, `pg-financial-aws-prod`) goes back to **2000-01-02** — **101 M rows /
43 % of the series live before 2015**. So a FactSet-only daily mcap **drops ~15 yr of history** (misses 2008, dot-com
…) — a real **regression**, not a product choice. Options: **(1) SPLICE (reco to keep daily)** = freeze Refinitiv
daily 2000→2015 + FactSet 2015→ ; coherent because `ent_mv` was chosen to match Refinitiv (~79-85 %) so the 2015
join is near-continuous; needs a one-shot freeze of the Refinitiv history (no live Refinitiv dependency). **(2)**
`ff_v3_ff_basic_der_af/qf`.`ff_mkt_val` = fundamentals-derived mcap back to **1979 (annual) / 1989 (quarterly)** but
LOW-frequency + STRICT price×shares convention (≈ `ent_mv_ex_treasury`, ≠ our total `ent_mv`) → a splice here adds a
2015 convention step. **(3)** accept 10 yr (hard to defend vs the 26 yr shipped today). No daily FactSet source older
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
