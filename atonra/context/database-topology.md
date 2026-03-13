# Database Topology

## Database Inventory

### PostgreSQL + TimescaleDB — Financial

Primary database for all financial data (reference, fundamentals, timeseries).

| Environment | Cluster | Infra | MCP Server |
|---|---|---|---|
| Production | `timescaledb-prd` | AWS K8s (CNPG) | `pg-financial-aws-prod` |
| Test/QA | Hetzner standalone | Hetzner | `pg-financial-hetzner-test` |

- **Projects using it:** fundy (pipelines, analytics, portfolios, optimizer)
- **Config location:** fundy infra assets (`cluster.yaml` for prod, Hetzner configured manually)
- **Schema and pipeline details:** see `dagster-patterns.md`

### Data patterns

- **Temporal versioning:** almost all tables use `temporal_tables` extension — each table has a corresponding `<table>_history` suffix table.
- **TimescaleDB hypertables:** timeseries data in master schema uses hypertables for partitioning and performance.

### PostgreSQL — Refinitiv QA

Current primary data source for market data. Feeds the financial database.

| Environment | Infra | MCP Server |
|---|---|---|
| QA | Hetzner (VPN required) | (none configured) |

- **Projects using it:** fundy (data ingestion pipelines)
- **Migration planned:** may migrate to FactSet as data provider

### PostgreSQL — Monitoring

Grafana and OpenObserve backend. **NOT the financial database.**

| Environment | Cluster | Infra |
|---|---|---|
| Production | `postgres-prd` | AWS K8s (CNPG) |

- NOT used for application queries — do not confuse with `timescaledb-prd`

### ClickHouse

Analytics and reporting engine.

| Environment | Infra | MCP Server |
|---|---|---|
| Production | AWS K8s | (to be configured) |
| Test | Hetzner | (to be configured) |

- **Projects using it:** fundy (data microservice, analytics)

## Structural Constraints

These are architectural constraints that do not change:

- **CNPG blocks ALTER SYSTEM** — on AWS K8s clusters, PostgreSQL parameters can only be changed via `cluster.yaml` (GitOps). Use `SET` for session-level testing only.
- **MCP connections are read-only** — cannot run DDL, DML, or SET parameters via MCP.
- **EXPLAIN without ANALYZE is safe** — read-only plan inspection, no risk to production data.
- **Hetzner is the initial performance baseline** — already tuned. Use as reference when comparing with prod until prod is properly parameterized, then prod becomes the baseline.

## Usage Guidelines

- Always verify which cluster you are targeting before running queries — `timescaledb-prd` (financial) vs `postgres-prd` (monitoring) are different databases.
- When investigating performance, compare baseline environment vs target — read actual parameters from the cluster, do not assume values.
- For parameter changes on prod: modify `cluster.yaml` in fundy infra assets, deploy via ArgoCD.
