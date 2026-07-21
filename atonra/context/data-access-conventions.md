# Data Access & Placement Conventions

Authority: `fundy/src/data/docs/serving/12-data-access-conventions.md` (decided 2026-07-16).
Summary for all sessions:

## Access (per consumer)

- One question: "do I PRODUCE something from this data, or only READ it?"
  - Read-only → query the platform (HTTP API between services; `serving` schema inside the data
    product). Copying data you don't transform is FORBIDDEN.
  - Produce → copy YOUR INPUTS from `master` (one hop), own the derived result in YOUR store.
  - Heavy timeseries compute → the computation goes TO ClickHouse; only your derived result
    comes back. Raw timeseries are never copied per service.
- "The API already serves it" is NOT an argument against a batch copy: the API is a request-time
  contract, not a bulk interface.
- No copy derives from another copy (one hop from master). Pipelines/ETL read `master`, never
  `serving`.

## Placement (per dataset) — 3 tests, stop at first fail

1. **Cycle**: content computed FROM master data never returns to master (ratios, factor scores).
   Resolving external ids to master ids is NOT a cycle.
2. **Domain**: app operational state (positions, watchlists) lives in its service, never master.
3. **Source contract**: master ingests only producers holding source-grade guarantees (external
   providers; slow internal human curation like workbench thematics). Fast-evolving algorithmic
   outputs (KG) → serving-composed, promotable later when the contract matures.

- master = what we certify and derive from; serving = what we display and compose.
- raw/staging = platform ingestion layers with TWO terminal homes (master or serving); the DAG
  is one-way, serving→master forbidden.

## ClickHouse ownership zones

`analytics` = platform golden copies • `signals` = compute-service published outputs
(feature_values, ratios, factor scores) • `mart_*` = consumer marts. Nobody reads another
consumer's mart. Dagster is the control plane (ordering/freshness/lineage), never the data plane.
