# Master Schema — Domain Map

109 tables in the `master` schema. Source-agnostic golden source for all financial reference data.
Temporal versioning via `temporal_tables` extension (`_history` suffix — 38 tables). TimescaleDB hypertables for timeseries.

## Entity Resolution (core join pattern)

Provider ID → `entity_mapping` (by `data_source_id`) → `entity_id` → domain tables.
Same pattern for instruments (`instrument_mapping`), quotes (`quote_mapping`), venues (`venue_mapping`).
All mapping tables reference `data_source` (currently: QA = Refinitiv). FactSet will be a new `data_source` entry.

## Domain: Core Entities

- `entity` (6 cols) → `entity_type` — Universal registry. Every company, instrument, index resolves here.
- `entity_mapping` (5 cols) — Links provider IDs to internal entity. FK: data_source, entity_type, entity.
- `entity_classification` (4 cols) — Assigns classification nodes (GICS, etc.) to entities.
- `entity_concept` (2 cols) — Tags entities with concepts (ESG, thematic, etc.).
- `entity_financial_ratio` (4 cols) — Pre-computed financial ratios per entity.

## Domain: Company

- `company` (27 cols) — Company attributes. FK: entity, country, currency (estimates + statements), parent company, ultimate org.
- `company_market_cap` (6 cols) — Daily market cap. FK: company, currency.
- `company_weblink` (6 cols) — URLs per type. FK: company, weblink_type.
- `competitor` (5 cols) — Company-to-company competitor relationships.

## Domain: Instruments

- `instrument` (8 cols) → `instrument_type` — Financial instruments. FK: entity, instrument_type.
- `instrument_mapping` (5 cols) — Provider instrument IDs. FK: data_source, instrument_type, instrument.

## Domain: Equity

- `equity` (17 cols) → `equity_type` — Equity-specific attributes (ISIN, SEDOL, CUSIP, ticker, etc.). FK: instrument, equity_type, country.
- `share_outstanding` (4 cols) — Share count timeseries. FK: equity.

## Domain: Quotes

- `quote` (12 cols) — Tradable listings on venues. FK: instrument, venue, currency.
- `quote_mapping` (4 cols) — Provider quote IDs. FK: data_source, quote.

## Domain: Market Data

- `market_data` (12 cols) — OHLCV timeseries. **Hypertable** on date. FK: quote, currency.
- `market_data_adjusted` (26 cols) — Corporate-action + dividend adjusted prices.
- `market_data_load` (6 cols) — Load tracking for incremental ingestion.
- `total_return` (4 cols) — Total return index. FK: quote.

## Domain: Financials

- `std_financial_filing` (17 cols) — Filing metadata (period, dates, currencies). FK: company, currency (reported + converted), financial_period_type.
- `std_financial_statement` (9 cols) — Statement within a filing. FK: filing, financial_statement_type.
- `std_financial_value` (10 cols) — Individual line items. FK: statement, item, company, period_type, statement_type.
- `std_financial_item` (5 cols) — Standardized item catalog. FK: financial_statement_type.
- `std_financial_item_mapping` (5 cols) — Provider item codes → internal items. FK: data_source, std_financial_item.

## Domain: Estimates

- `estimate_actual` (12 cols) — Reported actuals per item/period. FK: company, currency, estimate_item, estimate_period_type.
- `estimate_consensus` (22 cols) — Consensus stats (mean, median, high, low, etc.). FK: company, currency, estimate_item, estimate_period_type.
- `estimate_item` (3 cols) — Estimate item catalog.
- `estimate_period_type` (2 cols) — Period granularity (annual, quarterly, etc.).

## Domain: Corporate Actions

- `corpact_event` (15 cols) — Events (splits, mergers, spinoffs). FK: equity, corpact_type, currency.
- `corpact_adjustment` (7 cols) — Adjustment factors. FK: equity, corpact_type.
- `dividend` (11 cols) — Dividend events. FK: equity, dividend_type, currency.
- `dividend_adjustment` (9 cols) — Dividend adjustment factors. FK: equity, currency.

## Domain: Reference

- `country` (5 cols), `region` (4 cols), `country_region` (3 cols) — Geography hierarchy.
- `venue` (7 cols) → `venue_type` — Trading venues. FK: country, venue_type.
- `venue_mapping` (5 cols) — Provider venue IDs. FK: data_source, venue, venue_type.
- `currency` (5 cols), `currency_pair` (4 cols), `fx_rate` (7 cols) — Currency and FX.
- `classification_scheme` (5 cols), `classification_level` (4 cols), `classification_node` (6 cols) — Hierarchical classifications (GICS, ICB, etc.).
- `data_source` (4 cols) — Provider registry. Current: QA (Refinitiv).
- `financial_period_type` (5 cols), `financial_statement_type` (4 cols) — Financial taxonomy.
- `weblink_type` (3 cols) — URL categories.

## Domain: Derived / Analytics

- `market_metrics_primary` (7 cols) — Pre-computed primary quote metrics.
- `last_volatility` (7 cols), `last_metrics` (29 cols), `last_company_market_cap` (10 cols) — Latest snapshots.
- `factor_score` (6 cols) — Factor model scores.
- `gics_company_classification` (10 cols) — Denormalized GICS per company.
- `knowledge_graph_triplet` (11 cols) — Entity relationship graph.

## Domain: Portfolios

- `amc_universe` (3 cols), `amc_universe_with_rationale` (4 cols), `charles_universe` (2 cols) — Investment universes.

## Master Views (19)

Enriched/denormalized views for consumption: `company_enriched`, `equity_enriched`, `equity_listing`, `market_data_enriched`, `market_data_corp_adjusted`, `market_data_div_adjusted`, `market_data_adjusted_filled`, `daily_return`, `daily_return_filled`, `financial_value_enriched`, `dividend_enriched`, `corpact_event_enriched`, `fx_rate_enriched`, `company_market_cap_usd`, `equity_market_cap`, `last_market_data`, `liquidity`, `volatility`, `momentum`.

## Column-Level Detail

Query via MCP on demand — do not embed here:
- **Prod:** `mcp__pg-financial-aws-prod__execute_sql` (requires SSH tunnel on port 5434)
- **Test:** `mcp__pg-financial-hetzner-test__execute_sql`
