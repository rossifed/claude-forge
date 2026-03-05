---
description: "Data pipeline conventions for Atonra: Dagster orchestration, dbt transformations, ClickHouse. Auto-activates for pipeline codebases."
---

# Data / Orchestration Conventions

## Stack

- **Orchestrator:** Dagster (pipeline scheduling and monitoring)
- **Transformations:** dbt with ClickHouse adapter
- **dbt model layering:** staging -> intermediate -> mart
- **Auth:** OIDC via AWS Cognito

## Dagster Code Structure

- `definitions.py` is assembly only: imports + `Definitions(...)`. No asset definitions, no schedules, no business logic inline.
- Asset definitions, jobs, schedules, and sensors go in dedicated modules (e.g., `assets/`, `jobs/`, `schedules/`).
- Business logic (computations, data fetching, transformations) goes in separate modules, never in wiring files.
- This applies at every project scale, including prototypes and proofs of concept.
