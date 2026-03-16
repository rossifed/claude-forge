# Python Conventions

Non-default choices only — Claude handles standard Python conventions by default.

## Tooling

- Package manager: `uv` (not pip/poetry)
- Linter + formatter: `ruff` (not black + flake8/pylint)
- Type checker: `pyright` (not mypy)
- Tests: `pytest` with `pytest.mark.anyio` for async tests (not asyncio)

## Formatting

- Line length: 119 characters
- Double quotes for strings
