---
description: "Python conventions for Atonra: uv, ruff, pyright, FastAPI, SQLAlchemy, pytest. Auto-activates for Python codebases."
---

# Python Conventions

## Tooling

- **Python:** 3.12+
- **Package manager:** `uv` (with `uv.lock`). Never use pip directly.
- **Virtual env:** `.venv/` per service
- **Linter + formatter:** `ruff` (config in `pyproject.toml`)
- **Type checker:** `pyright` (strict)
- **Install deps:** `uv sync --all-groups`

## Style Decisions (non-default)

- Line length: 119
- Quotes: double quotes
- Union syntax: `X | None` (not `Optional[X]`)
- Generics: `list[X]`, `dict[K, V]` (not `List`, `Dict` from `typing`)
- DTOs and API schemas: always Pydantic `BaseModel`
- Configuration via environment variables + Pydantic `BaseSettings`

## FastAPI Patterns

- Response models: always Pydantic models, never raw dicts.
- Custom exception classes go in the `exceptions` module of each service.
- Log errors before raising; never expose internals in error messages.

## Database

- **PostgreSQL (transactional):** SQLAlchemy 2.0+ async + Alembic for migrations
- **ClickHouse (analytics):** `ibis-framework` for type-safe query building
- Connection factories in shared utils
- Mock database connections in tests (`MockIbisConnection`)

## Commands

- **Run all tests:** `uv run pytest`
- **Run one test:** `uv run pytest path/to/test.py::test_name` or `uv run pytest -k "keyword"`
- **Coverage:** `uv run pytest --cov=. --cov-report=html --cov-report=xml`
- **Lint:** `uv run ruff check .` and `uv run ruff format --check .`
- **Type check:** `uv run pyright`

## Testing

- `pytest` with `pytest.mark.anyio` for async tests
- `tests/` directory per service, `conftest.py` for shared fixtures
- Mock external dependencies (DB, auth, other services). Test both success and error paths.
