# Atonra Engineering Conventions

> Company-wide mandates only. Technology-specific conventions (Python, TypeScript,
> data pipelines) are managed as skills that auto-activate based on project context.
>
> Project-specific directives belong in each project's own `CLAUDE.md`.

---

## Architecture

- Microservice boundaries are strict: no imports across service boundaries.
- Inter-service communication: HTTP APIs only.
- Shared code goes in a dedicated shared module — never duplicate code across services.
- BFF pattern for authentication: tokens stored in HTTP-only cookies, never exposed to frontend JS.

## Git

- Commit messages validated by commitizen pre-commit hook.
- Pre-commit hooks: trailing-whitespace fix, end-of-file-fixer, YAML validation, large file check (max 2MB), ruff check + format (auto-fix).

## Secrets

- **Encryption:** SOPS for `.env.secrets` files (PGP keys)
- **Auto-decryption:** direnv (`.envrc`) on directory entry

## CI/CD

- **CI:** GitHub Actions (lint, type-check, test, build, deploy)
- **Container registry:** ghcr.io
- **Pipeline deployments:** Dagster Cloud
- **Kubernetes deployments:** ArgoCD (GitOps)
- **Infrastructure:** Terraform (AWS)
- **Docs:** MkDocs -> GitHub Pages

## Observability

- **Tracing:** OpenTelemetry (OTLP gRPC)
- **Metrics:** Prometheus + Grafana
- **Error tracking:** Sentry
- **Logging:** structured (JSON), never log sensitive data

## Development Environment

- All services must be runnable via `docker compose up`
- MkDocs with Material theme for documentation
- New features require documentation before merge
