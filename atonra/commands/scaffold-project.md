---
description: Scaffold a new Atonra project binary-compatible with fundy
allowed-tools: Write, Bash, Read, Glob, Grep, AskUserQuestion, Edit
---

# Scaffold Atonra Project

You are scaffolding a new Atonra project that is **binary-compatible with fundy** — any service created can be copy-pasted into `fundy/src/` and work immediately.

**Core principle: portability over originality.** Templates ARE fundy's patterns, generalized with placeholders.

---

## §1 Questionnaire

Collect all answers BEFORE generating any files. Ask one step at a time using `AskUserQuestion`. Validate inputs as specified.

### Step 1 — Project basics

Ask:
```
**Step 1/8 — Project basics**

1. **Project name** (kebab-case, e.g. `atlas`):
2. **Short description** (one line):
3. **Target directory** (default: `/home/frossi/dev/atonra/<project-name>`):
```

- Validate: name must be kebab-case (`^[a-z][a-z0-9-]*$`)
- Store as: `PROJECT_NAME`, `PROJECT_DESCRIPTION`, `TARGET_DIR`
- Derive: `PROJECT_NAME_SNAKE` (replace `-` with `_`), `PROJECT_NAME_UPPER` (uppercase), `NETWORK_NAME` (`<project>-network`)

### Step 2 — Data storage (local)

Ask:
```
**Step 2/8 — Local databases**

Which local databases do you need? (comma-separated, or "none")
- **PostgreSQL** (default port 5432)
- **ClickHouse** (default ports 8123/9000)
- **MinIO/S3** (default port 9000/9001)

For each, accept defaults or specify custom ports.
```

- Store as: `LOCAL_DBS` (list), `DB_PORTS` (map of db -> ports)

### Step 3 — External data sources + MCP discovery

Ask:
```
**Step 3/8 — External data sources**

Connect to external databases? (comma-separated, or "none")
Options: PostgreSQL, ClickHouse, MinIO, S3, MSSQL
```

For each selected source:
1. **Scan existing MCP servers** — read `~/.claude/settings.local.json` and look for MCP server names matching `{db}-{domain}-{infra}-{env}` pattern
2. **If MCP found**: show the match and ask if they want to reuse it
3. **If no MCP**: collect connection info (host, port, user, database, description) for `.env.secrets` template, then **propose creating an MCP server** entry

- Store as: `EXTERNAL_SOURCES` (list of {type, name, mcp_server_name, connection_details})

### Step 4 — Inter-service communication

Ask:
```
**Step 4/8 — Inter-service communication**

1. **HTTP sync** is always enabled (shared httpx async client with Bearer token propagation).

2. **Event-based / async messaging?** (y/n, default: n)
   If yes, scaffolds abstract event bus + commented Redis/RabbitMQ in docker-compose.

3. **Shared OLAP layer?** (y/n, default: based on ClickHouse selection)
   If yes, generates shared ibis ClickHouse connection util.
```

- Store as: `ENABLE_EVENTS`, `ENABLE_OLAP`

### Step 5 — Data pipeline (Dagster)

Ask:
```
**Step 5/8 — Data pipeline**

1. **Need Dagster orchestrator?** (no / local / local+cloud)
2. If yes, which tools? (comma-separated: dbt, sling, dlt)
```

- Store as: `DAGSTER_MODE` (none/local/cloud), `DAGSTER_TOOLS` (list)

### Step 6 — Services

Ask:
```
**Step 6/8 — Services**

How many services? Then for each:
1. **Name** (kebab-case)
2. **FastAPI API?** (y/n)
3. **Dagster code location?** (y/n) — adds `pipelines/` subfolder
4. **Own PostgreSQL database?** (y/n) — adds to postgres-init.sh
5. **Short description** — for SERVICE_CONTEXT.md
```

- Store as: `SERVICES` (list of {name, has_api, has_dagster, has_db, description})
- Validate: at least 1 service, names must be kebab-case

### Step 7 — Frontend

Ask:
```
**Step 7/8 — Frontend**

Need a frontend? (no / react-tanstack / other)
```

- Store as: `FRONTEND_TYPE`

### Step 8 — Confirmation

Display a summary table of ALL choices and ask for confirmation before proceeding.

```
**Step 8/8 — Confirmation**

| Setting | Value |
|---|---|
| Project | <name> — <description> |
| Directory | <target_dir> |
| Local DBs | <list> |
| External sources | <list with MCP info> |
| Communication | HTTP sync + <events if enabled> |
| OLAP layer | <yes/no> |
| Dagster | <mode> with <tools> |
| Services | <list with details> |
| Frontend | <type> |

Proceed with generation? (y/n)
```

---

## §2 MCP Discovery

When scanning for existing MCP servers:

```python
# Read these files in order, merge results:
# 1. ~/.claude/settings.local.json  (user-level)
# 2. <project>/.claude/settings.local.json  (project-level, if exists)
# Look for keys in "mcpServers" matching pattern: {db}-{domain}-{infra}-{env}
# db prefixes: pg (PostgreSQL), ch (ClickHouse), minio, s3, mssql
```

When proposing new MCP servers for the scaffolded project:
- PostgreSQL: use `@anthropic/mcp-postgres` with `postgresql://` connection string
- ClickHouse: use appropriate MCP package
- Follow naming convention: `{db}-{domain}-{infra}-{env}`

---

## §3 Generation Rules

Generate files conditionally based on questionnaire answers. Use the templates in §4.

### Always generated:
- `.github/workflows/` (empty directory with `.gitkeep`)
- `.claude/commands/` (empty directory with `.gitkeep`)
- `CLAUDE.md`
- `AGENTS.md`
- `README.md`
- `.gitignore`
- `.python-version`
- `pyproject.toml` (root)
- `.pre-commit-config.yaml`
- `.envrc`
- `.sops.yaml`
- `.env.secrets.example`
- `infrastructure/docker-compose/docker-compose.yml`
- `infrastructure/docker-compose/services/traefik.yml`
- `infrastructure/docker-compose/services/monitoring.yml`
- `src/shared/python/auth/` (full package)
- `src/shared/python/utils/` (full package)
- `src/shared/python/http_client/` (full package)
- `docs/mkdocs.yml` + `docs/docs/index.md`
- `gitops/README.md`
- `terraform/README.md`

### Conditional:
- `infrastructure/docker-compose/services/databases.yml` — if any local DB selected
- `infrastructure/docker-compose/init-scripts/postgres-init.sh` — if PostgreSQL selected
- `infrastructure/docker-compose/services/dagster.yml` — if Dagster enabled
- `infrastructure/docker-compose/services/microservices.yml` — if any service has FastAPI
- `.claude/settings.local.json` — if external sources with new MCP servers
- `src/shared/python/events/` — if events enabled
- `src/shared/python/utils/src/utils/ibis/connections/clickhouse.py` — if OLAP enabled
- Per service: full service directory structure (see §4)

---

## §4 Templates

Replace these placeholders in all templates:
- `{{PROJECT_NAME}}` — kebab-case project name (e.g. `atlas`)
- `{{PROJECT_NAME_SNAKE}}` — snake_case (e.g. `atlas`)
- `{{PROJECT_NAME_UPPER}}` — UPPER_CASE (e.g. `ATLAS`)
- `{{PROJECT_DESCRIPTION}}` — short description
- `{{NETWORK_NAME}}` — `<project>-network`
- `{{SERVICE_NAME}}` — kebab-case service name
- `{{SERVICE_NAME_SNAKE}}` — snake_case service name
- `{{SERVICE_DESCRIPTION}}` — service description
- `{{TRAEFIK_PORT}}` — default 8000
- `{{PG_PORT}}` — default 5432
- `{{CH_HTTP_PORT}}` — default 8123
- `{{CH_NATIVE_PORT}}` — default 9000
- `{{DAGSTER_PORT}}` — gRPC port, auto-increment from 4001 per code location

### CLAUDE.md

```markdown
# {{PROJECT_NAME}} — Project Instructions

> {{PROJECT_DESCRIPTION}}

## Architecture

This project follows the Atonra monorepo pattern (see `/home/frossi/dev/atonra/CLAUDE.md` for org-wide conventions).

### Project structure

- `src/<service>/` — portable service units (FastAPI + optional Dagster code location)
- `src/shared/python/` — shared libraries (auth, utils, http_client)
- `infrastructure/docker-compose/` — local development environment
- `docs/` — MkDocs documentation

### Service portability

Any `src/<service>/` directory can be copied into `fundy/src/` with minimal changes:
1. Add env vars to fundy's docker-compose microservices.yml
2. Add service entry in fundy's microservices.yml
3. If Dagster: add gRPC entry in fundy's dagster.yml
4. Shared libs use same relative paths (`../../shared/python/`)

## Stack

- **Runtime**: Python 3.12, uv
- **API**: FastAPI
- **DB**: SQLAlchemy + Alembic (PostgreSQL), ibis (ClickHouse)
- **Orchestration**: Dagster (if enabled)
- **Observability**: OpenTelemetry + Sentry + Prometheus
- **Auth**: JWT (HS256) with Bearer token propagation

## Development

```bash
# Start all services
docker compose -f infrastructure/docker-compose/docker-compose.yml --profile all up -d

# Start specific profile
docker compose -f infrastructure/docker-compose/docker-compose.yml --profile databases up -d
docker compose -f infrastructure/docker-compose/docker-compose.yml --profile services up -d
```
```

### AGENTS.md

```markdown
# {{PROJECT_NAME}} — Developer Guide

## Getting Started

1. Clone the repository
2. Install direnv and SOPS
3. Configure PGP keys in `.sops.yaml`
4. Encrypt your secrets: `sops -e .env.secrets > .env.secrets.enc`
5. Run `direnv allow`
6. Start services: `docker compose -f infrastructure/docker-compose/docker-compose.yml --profile all up -d`

## Adding a New Service

1. Create `src/<service-name>/` following the existing service structure
2. Add `pyproject.toml` with shared lib dependencies via `[tool.uv.sources]`
3. Add `Dockerfile` based on existing services
4. Add service entry in `infrastructure/docker-compose/services/microservices.yml`
5. If the service needs its own DB, add it to `infrastructure/docker-compose/init-scripts/postgres-init.sh`

## Shared Libraries

- `src/shared/python/auth/` — JWT verification (verify_token dependency)
- `src/shared/python/utils/` — FastAPI helpers, ibis connections
- `src/shared/python/http_client/` — Base async HTTP client with token propagation

Reference them in service `pyproject.toml`:
```toml
[tool.uv.sources]
auth = { path = "../shared/python/auth", editable = true }
utils = { path = "../shared/python/utils", editable = true }
http_client = { path = "../shared/python/http_client", editable = true }
```
```

### README.md

```markdown
# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Quick Start

```bash
# Decrypt secrets
sops -d .env.secrets.enc > .env.secrets
direnv allow

# Start all services
docker compose -f infrastructure/docker-compose/docker-compose.yml --profile all up -d
```

## Documentation

See `docs/` directory or run `mkdocs serve` for local docs.
```

### .gitignore

```
.env.secrets
.env.secrets.sha256

.vscode
.idea

*.ipynb

.DS_Store

# Python
__pycache__/
*.py[codz]
*$py.class
*.so
.Python
build/
dist/
*.egg-info/
*.egg
.venv
venv/
.ruff_cache/
.mypy_cache/
.pytest_cache/
htmlcov/
.coverage
.coverage.*
coverage.xml

# Docker
volumes/

# Node.js
node_modules/
.tanstack
.output
.nitro

# Bun
bun.lockb
.bun

# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
!terraform.tfvars

# Session tracking
SESSION.md
```

### .python-version

```
3.12
```

### Root pyproject.toml

```toml
[project]
name = "{{PROJECT_NAME_UPPER}}Dev"
authors = [{ name = "Atonra Team" }]
version = "0.0.1"
requires-python = ">=3.12"


[dependency-groups]
dev = [
  "pre-commit == 2.17.*",
  "commitizen == 3.2.*",
  "ruff == 0.15.*",
]

[tool.ruff]
line-length = 119
target-version = "py312"
exclude = ["venv", ".venv"]

[tool.ruff.lint]
select = [
    "E",        # pycodestyle
    "F",        # pyflakes
    "W",        # warnings
    "B",        # flake8-bugbear
    "I",        # isort
    "C90",      # McCabe complexity
    "N",        # pep8-naming
    "Q",        # flake8-quotes
    "S",        # Bandit (security)
    "T20",      # flake8-print
    "T100"      # flake8-debugger
]

ignore = ["D417", "E501"]

[tool.ruff.lint.per-file-ignores]
"**/tests/**/*.py" = ["S101", "S311", "S105", "S106"]

[tool.ruff.lint.mccabe]
max-complexity = 15

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"
```

### .pre-commit-config.yaml

```yaml
default_language_version:
    python: python3.12
repos:
-   repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v3.2.0
    hooks:
    -   id: trailing-whitespace
        stages: [commit]
    -   id: end-of-file-fixer
        stages: [commit]
    -   id: check-yaml
        stages: [commit]
    -   id: check-added-large-files
        args: ['--maxkb=2000']
        stages: [commit]

-   repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.4
    hooks:
        - id: ruff
          args: [ --fix ]
        - id: ruff-format
-   repo: https://github.com/commitizen-tools/commitizen
    rev: v3.2.2
    hooks:
    -   id: commitizen
    -   id: commitizen-branch
        stages: [push]
```

### .envrc

```bash
SOPS_ENV_FILE=".env.secrets.enc"
SOPS_DECRYPTED_FILE=".env.secrets"
SOPS_HASH_FILE=".env.secrets.sha256"

if [ -f "$SOPS_ENV_FILE" ]; then
  CURRENT_HASH=$(sha256sum "$SOPS_ENV_FILE" | cut -d ' ' -f1)

  if [ ! -f "$SOPS_HASH_FILE" ] || [ "$CURRENT_HASH" != "$(cat $SOPS_HASH_FILE)" ]; then
    echo "Decrypting $SOPS_ENV_FILE..."
    sops -d --input-type dotenv --output-type dotenv "$SOPS_ENV_FILE" > "$SOPS_DECRYPTED_FILE"
    echo "$CURRENT_HASH" > "$SOPS_HASH_FILE"
  fi

  source_env "$SOPS_DECRYPTED_FILE"
fi
```

### .sops.yaml

```yaml
creation_rules:
  - path_regex: '\.env\.secrets(\.enc)?$'
    pgp: >-
      REPLACE_WITH_YOUR_PGP_KEY_FINGERPRINTS
```

### .env.secrets.example

Generate based on selected features. Always include:
```bash
# === Auth ===
# FUNDY_AUTH_JWT_SECRET=your-jwt-secret-here
# FUNDY_AUTH_ISSUER=<project>-users
# FUNDY_AUTH_AUDIENCE=<project>-services

# === Sentry ===
# SENTRY_BACKEND_DSN=

# === Observability ===
# OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
# GRAFANA_CLOUD_API_KEY=
```

Add per-service DB URLs if applicable:
```bash
# === Service: <name> ===
# <NAME>_DATABASE_URL=postgresql+psycopg://postgres:password@localhost:5432/<name>
```

Add external source connection vars if applicable.

### docker-compose.yml

```yaml
include:
  - ./services/traefik.yml
  - ./services/databases.yml        # Only if local DBs selected
  - ./services/monitoring.yml
  - ./services/microservices.yml    # Only if any service has FastAPI
  - ./services/dagster.yml          # Only if Dagster enabled

networks:
  {{NETWORK_NAME}}:
    name: {{NETWORK_NAME}}
    driver: bridge
  monitoring:
    external: true
```

Only include lines for services that were selected.

### traefik.yml

```yaml
services:
  {{PROJECT_NAME}}-traefik:
    image: traefik:latest
    container_name: "{{PROJECT_NAME}}-traefik"
    profiles: [all, loadbalancer, services]
    command:
      - "--api.dashboard=true"
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--log.level=INFO"
      - "--ping=true"
    ports:
      - "{{TRAEFIK_PORT}}:80"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "traefik.enable=true"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    networks:
      - {{NETWORK_NAME}}

  {{PROJECT_NAME}}-traefik-whoami:
    image: "traefik/whoami"
    container_name: "{{PROJECT_NAME}}-traefik-whoami"
    profiles: [all, loadbalancer, services]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.localhost`)"
      - "traefik.http.routers.whoami.entrypoints=web"
    networks:
      - {{NETWORK_NAME}}
```

### databases.yml

Generate based on selected local databases:

**If PostgreSQL selected:**
```yaml
services:
  {{PROJECT_NAME}}-postgres:
    image: postgres:17
    container_name: {{PROJECT_NAME}}-postgres
    profiles: [all, databases]
    ports:
      - "{{PG_PORT}}:5432"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    volumes:
      - {{PROJECT_NAME}}-postgres-data:/var/lib/postgresql/data
      - ../init-scripts/postgres-init.sh:/docker-entrypoint-initdb.d/postgres-init.sh:ro
    networks:
      - {{NETWORK_NAME}}
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U postgres']
      interval: 10s
      timeout: 8s
      retries: 5
      start_period: 10s
    restart: unless-stopped

volumes:
  {{PROJECT_NAME}}-postgres-data:
```

**If ClickHouse selected:**
```yaml
  {{PROJECT_NAME}}-clickhouse:
    image: clickhouse/clickhouse-server:25.6-alpine
    container_name: {{PROJECT_NAME}}-clickhouse
    profiles: [all, databases]
    ports:
      - "{{CH_HTTP_PORT}}:8123"
      - "{{CH_NATIVE_PORT}}:9000"
      - "9009:9009"
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    volumes:
      - ../../../volumes/clickhouse:/var/lib/clickhouse
      - ../../../volumes/clickhouse-server:/var/log/clickhouse-server
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: default
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    networks:
      - {{NETWORK_NAME}}
```

**If MinIO selected:**
```yaml
  {{PROJECT_NAME}}-minio:
    image: minio/minio:latest
    container_name: {{PROJECT_NAME}}-minio
    profiles: [all, databases]
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes:
      - ../../../volumes/minio:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - {{NETWORK_NAME}}
```

### monitoring.yml

```yaml
services:
  grafana-alloy:
    image: grafana/alloy:latest
    profiles: [all, monitoring]
    command: run --server.http.listen-addr=0.0.0.0:12345 --storage.path=/var/lib/alloy/data /etc/alloy/config.alloy
    volumes:
      - ../../config/grafana/alloy-config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "127.0.0.1:12345:12345"
    environment:
      GRAFANA_CLOUD_API_KEY: ${GRAFANA_CLOUD_API_KEY}
    networks:
      - {{NETWORK_NAME}}

#  prometheus-app:
#    image: prom/prometheus:latest
#    restart: unless-stopped
#    container_name: prometheus-observer
#    ports:
#      - 9090:9090
#    volumes:
#      - ../../config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
#    networks:
#      - {{NETWORK_NAME}}
#
#  grafana:
#    image: grafana/grafana
#    container_name: grafana-observer
#    restart: unless-stopped
#    depends_on:
#      - prometheus-app
#    ports:
#      - 3001:3001
#    environment:
#      - GF_SECURITY_ADMIN_USER=admin
#      - GF_SECURITY_ADMIN_PASSWORD=admin
#      - GF_SERVER_HTTP_PORT=3001
#    networks:
#      - {{NETWORK_NAME}}
```

### microservices.yml (per service with has_api=true)

For each service, generate a block following this pattern:

```yaml
services:
  {{SERVICE_NAME}}:
    build:
      context: ../../..
      dockerfile: src/{{SERVICE_NAME}}/Dockerfile

    container_name: "{{SERVICE_NAME}}-service"
    image: {{PROJECT_NAME}}/{{SERVICE_NAME}}-service

    command: ["fastapi", "dev", "{{SERVICE_NAME_SNAKE}}/main.py", "--host", "0.0.0.0", "--port", "80"]

    environment:
      # Add DATABASE_URL if service has own DB
      # DATABASE_URL: ${<SERVICE_UPPER>_DATABASE_URL}
      # Add ClickHouse vars if OLAP enabled
      # CLICKHOUSE_HOST: ${CLICKHOUSE_HOST}
      # CLICKHOUSE_PORT: ${CLICKHOUSE_PORT}
      # CLICKHOUSE_USERNAME: ${CLICKHOUSE_USERNAME}
      # CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}
      FUNDY_AUTH_JWT_SECRET: ${FUNDY_AUTH_JWT_SECRET}
      FUNDY_AUTH_ISSUER: ${FUNDY_AUTH_ISSUER:-{{PROJECT_NAME}}-users}
      FUNDY_AUTH_AUDIENCE: ${FUNDY_AUTH_AUDIENCE:-{{PROJECT_NAME}}-services}
      SENTRY_BACKEND_DSN: ${SENTRY_BACKEND_DSN}
      OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT}

    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.{{SERVICE_NAME}}.rule=PathPrefix(`/api/{{SERVICE_NAME}}`)"
      - "traefik.http.routers.{{SERVICE_NAME}}.middlewares={{SERVICE_NAME}}-stripprefix"
      - "traefik.http.middlewares.{{SERVICE_NAME}}-stripprefix.stripprefix.prefixes=/api/{{SERVICE_NAME}}"

    volumes:
      - ../../../src/{{SERVICE_NAME}}/{{SERVICE_NAME_SNAKE}}:/src/{{SERVICE_NAME}}/{{SERVICE_NAME_SNAKE}}:ro

    networks:
      - {{NETWORK_NAME}}

    deploy:
      replicas: 1

    profiles: [all, services]

    restart: unless-stopped

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

Uncomment DATABASE_URL line if service has own DB. Uncomment ClickHouse vars if OLAP enabled.

### dagster.yml (if Dagster enabled)

For each service with `has_dagster=true`, generate a gRPC code location. Port auto-increments from 4001.

```yaml
services:
  {{SERVICE_NAME}}-dagster-grpc:
    build:
      context: ../../..
      dockerfile: src/{{SERVICE_NAME}}/docker/Dockerfile_code
    container_name: {{SERVICE_NAME}}-dagster-grpc
    image: {{PROJECT_NAME}}/{{SERVICE_NAME}}-dagster-grpc
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-root}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-root}
      POSTGRES_DB: ${POSTGRES_DB:-{{PROJECT_NAME}}}
    networks:
      - {{NETWORK_NAME}}
    profiles: [dagster, all]
    healthcheck:
      test: ["CMD", "python", "-c", "import socket; s = socket.socket(); s.connect(('localhost', {{DAGSTER_PORT}})); s.close()"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 5s

  dagster-webserver:
    build:
      context: ../../..
      dockerfile: infrastructure/docker-compose/dagster/Dockerfile_webserver
    profiles: [dagster, all]
    entrypoint:
      - dagster-webserver
      - -h
      - '0.0.0.0'
      - -p
      - '3010'
      - -w
      - workspace.yaml
      - --path-prefix
      - '/dagster'
    container_name: {{PROJECT_NAME}}-dagster-webserver
    image: {{PROJECT_NAME}}/dagster-webserver
    expose:
      - '3010'
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-root}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-root}
      POSTGRES_DB: ${POSTGRES_DB:-{{PROJECT_NAME}}}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /tmp/io_manager_storage:/tmp/io_manager_storage
    networks:
      - {{NETWORK_NAME}}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dagster.rule=PathPrefix(`/dagster`)"
      - "traefik.http.routers.dagster.entrypoints=web"
      - "traefik.http.services.dagster.loadbalancer.server.port=3010"
      - "traefik.http.middlewares.dagster-ws.headers.customrequestheaders.Upgrade="
      - "traefik.http.middlewares.dagster-ws.headers.customrequestheaders.Connection="
      - "traefik.http.middlewares.dagster-ws.headers.customrequestheaders.Sec-WebSocket-Key="
      - "traefik.http.middlewares.dagster-ws.headers.customrequestheaders.Sec-WebSocket-Version="
      - "traefik.http.middlewares.dagster-ws.headers.customrequestheaders.Sec-WebSocket-Extensions="
      - "traefik.http.routers.dagster.middlewares=dagster-ws"
    depends_on:
      {{SERVICE_NAME}}-dagster-grpc:
        condition: service_healthy

  dagster-daemon:
    build:
      context: ../../..
      dockerfile: infrastructure/docker-compose/dagster/Dockerfile_webserver
    entrypoint:
      - dagster-daemon
      - run
    container_name: {{PROJECT_NAME}}-dagster-daemon
    image: {{PROJECT_NAME}}/dagster-daemon
    restart: on-failure
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-root}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-root}
      POSTGRES_DB: ${POSTGRES_DB:-{{PROJECT_NAME}}}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /tmp/io_manager_storage:/tmp/io_manager_storage
    networks:
      - {{NETWORK_NAME}}
    depends_on:
      {{SERVICE_NAME}}-dagster-grpc:
        condition: service_healthy
    profiles: [dagster, all]
```

### postgres-init.sh

```bash
#!/bin/bash
set -e

# Create databases for each microservice if they don't exist
for db in {{DB_LIST}}; do
  psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1 || \
  psql -U postgres -c "CREATE DATABASE $db"
  echo "Database '$db' is ready"
done

echo "All databases initialized successfully"
```

Where `{{DB_LIST}}` is a space-separated list of service names that have `has_db=true`.

### Service Dockerfile (FastAPI)

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /src/{{SERVICE_NAME}}

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Copy shared libraries first
COPY src/shared/python /src/shared/python

# Install dependencies without the project itself
RUN --mount=type=bind,source=src/{{SERVICE_NAME}}/uv.lock,target=/src/{{SERVICE_NAME}}/uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=src/{{SERVICE_NAME}}/pyproject.toml,target=/src/{{SERVICE_NAME}}/pyproject.toml \
    uv sync --locked --no-install-project --no-dev

# Copy the service application code
COPY src/{{SERVICE_NAME}} /src/{{SERVICE_NAME}}

# Install the project itself
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

ENV PATH="/src/{{SERVICE_NAME}}/.venv/bin:$PATH"

ENTRYPOINT []

EXPOSE 80

CMD ["fastapi", "run", "{{SERVICE_NAME_SNAKE}}/main.py", "--host", "0.0.0.0", "--port", "80"]
```

### Service Dockerfile_code (Dagster gRPC code location)

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

RUN apt-get update && apt-get install -y curl git && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/dagster/app

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

COPY src/{{SERVICE_NAME}}/pipelines/pyproject.toml src/{{SERVICE_NAME}}/pipelines/uv.lock* ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-dev

COPY src/{{SERVICE_NAME}}/pipelines ./pipelines

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

ENV PATH="/opt/dagster/app/.venv/bin:$PATH"
ENV PYTHONPATH=/opt/dagster/app

EXPOSE {{DAGSTER_PORT}}

CMD ["dagster", "api", "grpc", "-h", "0.0.0.0", "-p", "{{DAGSTER_PORT}}", "-m", "pipelines.definitions"]
```


### Service pyproject.toml

```toml
[project]
name = "{{SERVICE_NAME}}"
description = "{{SERVICE_DESCRIPTION}}"
authors = [{ name = "Atonra Team" }]
version = "0.0.1"
requires-python = ">=3.12"

dependencies = [
    "fastapi[standard]>=0.116.1",
    "auth",
    "utils",
    "sentry-sdk[fastapi]>=2.42.1",
    "prometheus-fastapi-instrumentator>=7.1.0",
    "opentelemetry-instrumentation-fastapi>=0.59b0",
    "opentelemetry-instrumentation-requests>=0.59b0",
    "opentelemetry-exporter-otlp-proto-grpc>=1.38.0",
    "opentelemetry-api>=1.38.0",
    "opentelemetry-sdk>=1.38.0",
    "http_client",
]

[tool.uv.sources]
auth = { path = "../shared/python/auth", editable = true }
utils = { path = "../shared/python/utils", editable = true }
http_client = { path = "../shared/python/http_client", editable = true }

[tool.uv]
package = true

[tool.hatch.build]
include = ["{{SERVICE_NAME_SNAKE}}/**/*.py"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[dependency-groups]
dev = [
    "pytest>=8.0.0",
    "pytest-anyio>=0.0.0",
    "httpx>=0.28.0",
    "ruff==0.15.*",
    "pyright>=1.1.0",
]

[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]

[tool.ruff]
extend = "../../pyproject.toml"

[tool.pyright]
pythonVersion = "3.12"
typeCheckingMode = "standard"
```

If service has own DB, add to dependencies:
```toml
    "psycopg[binary]>=3.2.9",
    "sqlalchemy[asyncio]>=2.0",
```

If service has Dagster, add to pyproject.toml:
```toml
[tool.dg]
directory_type = "project"

[tool.dg.project]
root_module = "pipelines"
code_location_target_module = "pipelines.definitions"
```

### Service pipelines/pyproject.toml (if Dagster)

```toml
[project]
name = "{{SERVICE_NAME}}-pipelines"
description = "{{SERVICE_NAME}} Dagster code location"
authors = [{ name = "Atonra Team" }]
version = "0.0.1"
requires-python = ">=3.12"

dependencies = [
    "dagster==1.12.15",
    "dagster-cloud==1.12.15",
    "dagster-postgres>=0.28.15",
]

[tool.uv]
package = true

[tool.hatch.build]
include = ["pipelines/**/*.py"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
extend = "../../../pyproject.toml"

[tool.pyright]
pythonVersion = "3.12"
typeCheckingMode = "standard"
```

If dbt selected, add `"dagster-dbt>=0.28.15"` and `"dbt-postgres>=1.9.0"` to dependencies.
If sling selected, add `"dagster-embedded-elt>=0.28.15"` and `"sling>=1.0.0"`.
If dlt selected, add `"dagster-dlt>=0.28.15"` and `"dlt>=0.4.0"`.

### Service main.py (FastAPI)

```python
"""{{SERVICE_DESCRIPTION}} — FastAPI application."""

import logging
import os
from contextlib import asynccontextmanager

import sentry_sdk
from auth._jwt import verify_token
from fastapi import Depends, FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_fastapi_instrumentator import Instrumentator as PrometheusInstrumentator
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

logger = logging.getLogger("{{SERVICE_NAME_SNAKE}}")
DEBUG = os.environ.get("DEBUG", "True") == "True"


def enable_sentry():
    if not DEBUG:
        if dsn := os.environ.get("SENTRY_BACKEND_DSN"):
            sentry_sdk.init(
                dsn=dsn,
                send_default_pii=True,
                integrations=[
                    StarletteIntegration(
                        transaction_style="endpoint",
                    ),
                    FastApiIntegration(
                        transaction_style="endpoint",
                    ),
                ],
                environment="production",
            )
            sentry_sdk.set_tag("service", "{{SERVICE_NAME_SNAKE}}")
            logger.info("Sentry enabled")
        else:
            logger.warning("Sentry not enabled due to missing DSN")


def enable_tracing():
    if exporter_endpoint := os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"):
        resource = Resource.create(attributes={"service.name": "{{SERVICE_NAME_SNAKE}}"})
        tracer_provider = TracerProvider(resource=resource)
        processor = BatchSpanProcessor(
            OTLPSpanExporter(
                endpoint=exporter_endpoint,
                insecure=True,
            )
        )
        tracer_provider.add_span_processor(processor)
        trace.set_tracer_provider(tracer_provider)
        logger.info("Tracing enabled")
    else:
        logger.warning("Tracing not enabled due to missing OTEL Exporter endpoint")


def create_lifespan_handler(instrumentator: PrometheusInstrumentator):
    """Create a FastAPI lifespan handler for the application."""

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        instrumentator.expose(app)
        yield

    return lifespan


def create_app() -> FastAPI:
    instrumentator = PrometheusInstrumentator()
    app = FastAPI(
        title="{{PROJECT_NAME_UPPER}} {{SERVICE_NAME}} Microservice API",
        version="1.0.0",
        root_path="/api/{{SERVICE_NAME}}",
        lifespan=create_lifespan_handler(instrumentator),
    )
    auth_deps = [Depends(verify_token)]
    # TODO: Add your routers here
    # app.include_router(your_router, prefix="/your-prefix", tags=["your-tag"], dependencies=auth_deps)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="^/health,^/metrics,/static/.*")
    return app


enable_sentry()
enable_tracing()
app = create_app()


@app.get("/health")
async def health_check():
    return {"status": "healthy"}
```

### Service __init__.py

```python
```

(empty file)

### Service db/engine.py (if service has own DB)

```python
import os

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

DATABASE_URL = os.environ["DATABASE_URL"]

engine = create_async_engine(DATABASE_URL, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
```

### Service db/fastapi.py (if service has own DB)

```python
from collections.abc import AsyncGenerator

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from {{SERVICE_NAME_SNAKE}}.db.engine import async_session


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session


SessionDep = Depends(get_session)
```

### Service db/__init__.py (if service has own DB)

```python
```

(empty file)

### Service db/models/__init__.py (if service has own DB)

```python
```

(empty file)

### Service api/__init__.py

```python
```

(empty file)

### Service services/__init__.py

```python
```

(empty file)

### Service schemas/__init__.py

```python
```

(empty file)

### Service clients/__init__.py

```python
```

(empty file)

### Service pipelines/__init__.py (if Dagster)

```python
```

(empty file)

### Service pipelines/definitions.py (if Dagster)

```python
import dagster as dg


defs = dg.Definitions(
    assets=[],
    schedules=[],
    sensors=[],
)
```

### Service tests/__init__.py

```python
```

(empty file)

### Service SERVICE_CONTEXT.md

```markdown
# {{SERVICE_NAME}} — Service Context

> {{SERVICE_DESCRIPTION}}

## Architecture

- **Type**: FastAPI microservice
- **API prefix**: `/api/{{SERVICE_NAME}}`
- **Database**: {{yes/no with details}}
- **Dagster code location**: {{yes/no}}

## Key Patterns

- Auth: JWT via `auth._jwt.verify_token` dependency
- Observability: Sentry + OpenTelemetry + Prometheus metrics
- HTTP clients: Use `http_client` shared lib for inter-service calls

## Directory Structure

```
{{SERVICE_NAME}}/
├── {{SERVICE_NAME_SNAKE}}/       # FastAPI app code
│   ├── main.py                   # Application entry point
│   ├── api/                      # Route handlers
│   ├── services/                 # Business logic
│   ├── db/                       # Database (if applicable)
│   ├── schemas/                  # Pydantic DTOs
│   └── clients/                  # HTTP clients to other services
├── pipelines/                    # Dagster code location (if applicable)
├── tests/
└── Dockerfile
```
```

### Shared auth package

Create `src/shared/python/auth/` with:

**pyproject.toml:**
```toml
[project]
name = "auth"
version = "0.1.0"
description = "JWT authentication shared library"
authors = [{ name = "Atonra Team" }]
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115.14",
    "httpx>=0.28.1",
    "pyjwt[crypto]>=2.10.1",
]

[dependency-groups]
dev = [
    "pytest>=8.4.1",
    "pytest-coverage>=0.0",
    "pytest-mock>=3.14.1",
    "ruff==0.15.*",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.pyright]
venv = ".venv"
venvPath = "."
reportExplicitAny = false

[tool.ruff]
extend = "../../../../pyproject.toml"
```

**src/auth/__init__.py:** (empty)

**src/auth/_jwt.py:**
```python
import os
from typing import Annotated, Any, cast

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

security = HTTPBearer()
security_optional = HTTPBearer(auto_error=False)


def _is_enabled(env_name: str, default: bool = False) -> bool:
    raw_value = os.environ.get(env_name)
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


def _decode_fundy_token(token: str) -> dict[str, Any]:
    auth_secret = os.environ["FUNDY_AUTH_JWT_SECRET"]
    audience = os.environ.get("FUNDY_AUTH_AUDIENCE")
    issuer = os.environ.get("FUNDY_AUTH_ISSUER")
    decode_options: dict[str, Any] = {}
    if audience is None:
        decode_options["verify_aud"] = False

    return cast(
        dict[str, Any],
        jwt.decode(
            token,
            key=auth_secret,
            algorithms=["HS256"],
            audience=audience,
            issuer=issuer,
            options=decode_options,
        ),
    )


def _decode_cognito_token(token: str) -> dict[str, Any]:
    jwks_client = jwt.PyJWKClient(os.environ["FUNDY_COGNITO_JWKS_URL"])
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    return cast(
        dict[str, Any],
        jwt.decode(
            token,
            key=signing_key,
            algorithms=[signing_key.algorithm_name],
        ),
    )


def verify_token(credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)]) -> dict[str, Any]:
    token = credentials.credentials
    try:
        return _decode_token(token)

    except jwt.PyJWTError as err:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        ) from err

    except KeyError as err:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server configuration error",
        ) from err


def _decode_token(token: str) -> dict[str, Any]:
    """Decode and verify a JWT token. Raises jwt.PyJWTError on failure."""
    decode_errors: list[Exception] = []

    if "FUNDY_AUTH_JWT_SECRET" in os.environ:
        try:
            return _decode_fundy_token(token)
        except jwt.PyJWTError as err:
            decode_errors.append(err)

    if _is_enabled("FUNDY_AUTH_ACCEPT_COGNITO", default=True):
        try:
            return _decode_cognito_token(token)
        except (jwt.PyJWTError, KeyError) as err:
            decode_errors.append(err)

    if decode_errors:
        for err in decode_errors:
            if isinstance(err, jwt.PyJWTError):
                raise err
            if isinstance(err, KeyError):
                raise err

    raise KeyError("Missing authentication verification settings")


def verify_token_or_anonymous(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(security_optional)] = None,
) -> dict[str, Any]:
    """Verify JWT token for authenticated and trial users.

    Returns:
        - {"type": "authenticated", "sub": "...", ...} for regular users
        - {"type": "anonymous", "session_id": "...", ...} for trial JWT users

    Raises:
        HTTPException(401) if no JWT is provided
        HTTPException(401) if JWT is invalid
        HTTPException(500) if server configuration error
    """
    if credentials:
        try:
            decoded = _decode_token(credentials.credentials)
            return {"type": "authenticated", **decoded}
        except jwt.PyJWTError as err:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials",
                headers={"WWW-Authenticate": "Bearer"},
            ) from err
        except KeyError as err:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Server configuration error",
            ) from err

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"},
    )
```

### Shared utils package

Create `src/shared/python/utils/` with:

**pyproject.toml:**
```toml
[project]
name = "utils"
version = "0.1.0"
description = "Shared utilities"
authors = [{ name = "Atonra Team" }]
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115.14",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.pyright]
venv = ".venv"
venvPath = "."

[tool.ruff]
extend = "../../../../pyproject.toml"
```

If OLAP enabled, add to dependencies:
```toml
    "ibis-framework[clickhouse]>=10.8.0",
```

**src/utils/__init__.py:** (empty)

**src/utils/fastapi/__init__.py:** (empty)

**src/utils/fastapi/response.py:**
```python
from pydantic import BaseModel


class Response[T](BaseModel):
    count: int
    data: list[T]
```

If OLAP enabled, also create:

**src/utils/ibis/__init__.py:** (empty)

**src/utils/ibis/connections/__init__.py:** (empty)

**src/utils/ibis/connections/clickhouse.py:**
```python
import os

import ibis
from ibis.backends.clickhouse import Backend as ClickhouseBackend


def get_ibis_clickhouse_connection() -> ClickhouseBackend:
    return ibis.clickhouse.connect(
        host=os.environ["CLICKHOUSE_HOST"],
        port=os.environ["CLICKHOUSE_PORT"],
        user=os.environ["CLICKHOUSE_USERNAME"],
        password=os.environ["CLICKHOUSE_PASSWORD"],
    )
```

### Shared http_client package

Create `src/shared/python/http_client/` with:

**pyproject.toml:**
```toml
[project]
name = "http_client"
version = "0.1.0"
description = "Shared async HTTP client with Bearer token propagation"
authors = [{ name = "Atonra Team" }]
requires-python = ">=3.12"
dependencies = [
    "httpx>=0.28.1",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
extend = "../../../../pyproject.toml"
```

**src/http_client/__init__.py:** (empty)

**src/http_client/base.py:**
```python
import httpx


class BaseServiceClient:
    """Base async HTTP client with Bearer token propagation.

    Subclass and add service-specific methods. Token is propagated
    from the incoming request to outgoing inter-service calls.
    """

    def __init__(
        self,
        base_url: str,
        token: str | None = None,
        timeout: float = 30.0,
    ):
        self.base_url = base_url
        self.token = token
        self.timeout = httpx.Timeout(timeout)

    def _headers(self) -> dict[str, str]:
        headers: dict[str, str] = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    async def _get(self, path: str, params: dict | None = None) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}{path}",
                params=params,
                headers=self._headers(),
            )
            response.raise_for_status()
            return response

    async def _post(self, path: str, json: dict | list | None = None) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}{path}",
                json=json,
                headers=self._headers(),
            )
            response.raise_for_status()
            return response

    async def _put(self, path: str, json: dict | list | None = None) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.put(
                f"{self.base_url}{path}",
                json=json,
                headers=self._headers(),
            )
            response.raise_for_status()
            return response

    async def _delete(self, path: str) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.delete(
                f"{self.base_url}{path}",
                headers=self._headers(),
            )
            response.raise_for_status()
            return response
```

### Shared events package (if events enabled)

Create `src/shared/python/events/` with:

**pyproject.toml:**
```toml
[project]
name = "events"
version = "0.1.0"
description = "Abstract event bus interface"
authors = [{ name = "Atonra Team" }]
requires-python = ">=3.12"
dependencies = []

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
extend = "../../../../pyproject.toml"
```

**src/events/__init__.py:** (empty)

**src/events/bus.py:**
```python
from abc import ABC, abstractmethod
from typing import Any


class EventBus(ABC):
    """Abstract event bus interface.

    Implement with Redis Streams, RabbitMQ, or another broker.
    """

    @abstractmethod
    async def publish(self, topic: str, payload: dict[str, Any]) -> None:
        """Publish an event to a topic."""

    @abstractmethod
    async def subscribe(self, topic: str, handler: Any) -> None:
        """Subscribe to events on a topic."""

    @abstractmethod
    async def close(self) -> None:
        """Clean up connections."""
```

### .claude/settings.local.json (if external MCP servers)

```json
{
  "mcpServers": {
    "{{MCP_SERVER_NAME}}": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic/mcp-postgres",
        "{{CONNECTION_STRING}}"
      ]
    }
  }
}
```

### docs/mkdocs.yml

```yaml
site_name: {{PROJECT_NAME_UPPER}}
theme:
  name: material
nav:
  - Home: index.md
```

### docs/docs/index.md

```markdown
# {{PROJECT_NAME_UPPER}}

{{PROJECT_DESCRIPTION}}
```

### dagster_home/dagster.yaml (if Dagster enabled)

```yaml
telemetry:
  enabled: false

concurrency:
  default_op_concurrency_limit: 2

run_coordinator:
  module: dagster.core.run_coordinator
  class: DefaultRunCoordinator

run_storage:
  module: dagster_postgres.run_storage
  class: PostgresRunStorage
  config:
    postgres_db:
      username:
        env: DAGSTER_PG_USER
      password:
        env: DAGSTER_PG_PASSWORD
      hostname:
        env: DAGSTER_PG_HOST
      db_name:
        env: DAGSTER_PG_DB
      port:
        env: DAGSTER_PG_PORT

event_log_storage:
  module: dagster_postgres.event_log
  class: PostgresEventLogStorage
  config:
    postgres_db:
      username:
        env: DAGSTER_PG_USER
      password:
        env: DAGSTER_PG_PASSWORD
      hostname:
        env: DAGSTER_PG_HOST
      db_name:
        env: DAGSTER_PG_DB
      port:
        env: DAGSTER_PG_PORT

schedule_storage:
  module: dagster_postgres.schedule_storage
  class: PostgresScheduleStorage
  config:
    postgres_db:
      username:
        env: DAGSTER_PG_USER
      password:
        env: DAGSTER_PG_PASSWORD
      hostname:
        env: DAGSTER_PG_HOST
      db_name:
        env: DAGSTER_PG_DB
      port:
        env: DAGSTER_PG_PORT
```

### dagster_cloud.yaml (if Cloud Agent mode, per service with Dagster)

```yaml
locations:
  - location_name: {{SERVICE_NAME}}-pipelines
    code_source:
      module_name: pipelines.definitions
    build:
      directory: ./
      registry: ghcr.io/atonra/{{PROJECT_NAME}}-{{SERVICE_NAME}}-pipelines
```

### gitops/README.md

```markdown
# GitOps — ArgoCD

ArgoCD deployment manifests go here. See Atonra CI/CD conventions.
```

### terraform/README.md

```markdown
# Terraform — Infrastructure

Terraform configurations for AWS infrastructure. See Atonra CI/CD conventions.
```

### .github/workflows/.gitkeep

(empty file)

### .claude/commands/.gitkeep

(empty file)

---

## §5 Post-generation

After all files are written:

1. **Initialize git repository:**
   ```bash
   cd <TARGET_DIR>
   git init
   git checkout -b main
   ```

2. **Install pre-commit hooks:**
   ```bash
   cd <TARGET_DIR>
   pip install pre-commit 2>/dev/null || true
   pre-commit install 2>/dev/null || true
   ```

3. **Display completion message** with:
   - List of generated files (grouped by category)
   - Next steps:
     - Fill in `.sops.yaml` PGP key fingerprints
     - Create `.env.secrets` from `.env.secrets.example`
     - Encrypt: `sops -e .env.secrets > .env.secrets.enc`
     - Run `direnv allow`
     - Start services: `docker compose -f infrastructure/docker-compose/docker-compose.yml --profile all up -d`
   - Portability reminder: any `src/<service>/` can be copied into `fundy/src/`

4. **Do NOT create an initial commit** — let the user review first.
