---
description: "Bootstrap a new Atonra project with the correct structure, tooling, and CLAUDE.md."
disable-model-invocation: true
user_invocable: true
---

# Scaffold — New Atonra Project

You are bootstrapping a new project that follows Atonra engineering conventions.

## Workflow

1. **Ask project type** (one of):
   - Python service (FastAPI microservice)
   - React frontend (TanStack Start)
   - Data pipeline (Dagster + dbt)
   - Full-stack (Python backend + React frontend monorepo)
   - Library (Python package, no service infrastructure)

2. **Ask database needs** (if applicable):
   - PostgreSQL (transactional)
   - ClickHouse (analytics)
   - Both
   - None

3. **Ask domain** (optional):
   - Fintech (financial data handling)
   - General

4. **Generate the project skeleton** based on answers.

5. **Generate a project-level `CLAUDE.md`** that references skills by description — never duplicates skill content.

## Generated Structure by Project Type

### Python service
```
pyproject.toml          # uv, ruff config, pyright
src/<service_name>/
    __init__.py
    main.py             # FastAPI app factory
    config.py           # Pydantic BaseSettings
    exceptions.py
    routes/
    models/
    schemas/
tests/
    conftest.py
Dockerfile
.pre-commit-config.yaml
.envrc                  # direnv + SOPS
.env.example
```

### React frontend
```
package.json            # bun, TanStack Start
app/
    routes/
    components/
    utils/
tsconfig.json
.prettierrc             # single quotes
.env.example
```

### Data pipeline
```
pyproject.toml          # uv, ruff config, pyright
definitions.py          # Dagster Definitions (assembly only)
assets/
jobs/
schedules/
sensors/
dbt/
    dbt_project.yml
    models/
        staging/
        intermediate/
        mart/
tests/
    conftest.py
.pre-commit-config.yaml
.envrc
.env.example
```

### Full-stack (monorepo)
```
services/
    <backend_name>/     # same as Python service layout
frontend/               # same as React frontend layout
docker-compose.yml
.pre-commit-config.yaml
.envrc
.env.example
```

### Library
```
pyproject.toml          # uv, ruff config, pyright
src/<package_name>/
    __init__.py
tests/
    conftest.py
.pre-commit-config.yaml
```

## Generated CLAUDE.md Template

The project CLAUDE.md must follow this pattern:

```markdown
# <Project Name>

<One-line description of what this project does.>

## Structure

<Brief description of directory layout and key files.>

## Key Commands

<Project-specific commands only — standard commands are in the tech skills.>

## Project-Specific Rules

<Rules unique to THIS project that override or extend skill defaults.>
```

## Rules

- No placeholder content ("TODO", "lorem ipsum", "example"). Every generated file must be functional.
- Match Atonra conventions exactly — use the tech skills as the source of truth for tooling and style.
- If the target directory is not empty, ask before generating. Never overwrite existing files without confirmation.
- Generate `.env.example` with descriptive dummy values, never real secrets.
- Include `.gitignore` appropriate for the project type.
- Do not generate CI/CD config — that follows company standards and is added separately.
