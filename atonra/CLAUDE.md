# Atonra Engineering Conventions

> Company-wide mandates only. Project-specific directives belong in each project's own `CLAUDE.md`.

## Architecture

- Microservice boundaries are strict: no imports across service boundaries — use HTTP APIs for inter-service communication.
- Shared code goes in a dedicated shared module — never duplicate across services.
- BFF pattern for authentication: tokens stored in HTTP-only cookies, never exposed to frontend JS.

## Git

- Pre-commit hooks are enforced: commitizen, ruff, trailing-whitespace, end-of-file-fixer, YAML validation, large file check (2MB). Do not bypass them — fix the underlying issue instead.

## Secrets

- Encrypt secrets with SOPS (`.env.secrets` files, PGP keys) — never commit plaintext secrets.
- Auto-decryption via direnv (`.envrc`) on directory entry.

## CI/CD & Infrastructure

- CI: GitHub Actions. Container registry: ghcr.io. K8s deployments: ArgoCD (GitOps). Infra: Terraform (AWS). Pipelines: Dagster Cloud.
- When creating CI workflows, Docker images, or deployment configs, use these tools — do not suggest alternatives.

## Observability

- Tracing: OpenTelemetry (OTLP gRPC). Metrics: Prometheus + Grafana. Errors: Sentry.
- Logging must be structured (JSON) — never log sensitive data, redact or omit instead.

## Development Environment

- All services must be runnable via `docker compose up`.
- Documentation: MkDocs with Material theme → GitHub Pages. New features require documentation before merge.

## Infrastructure Context

@context/database-topology.md
@context/dagster-patterns.md

## Stack Conventions

@context/python-conventions.md
@context/react-conventions.md
