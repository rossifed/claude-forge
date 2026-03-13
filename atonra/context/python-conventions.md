# Python Conventions

## Tooling

- Package manager: `uv`
- Linter + formatter: `ruff`
- Type checker: `pyright`
- Tests: `pytest`

## Formatting

- Line length: 119 characters
- Double quotes for strings
- Spaces for indentation (not tabs)
- Imports sorted by isort (enforced by ruff): standard library → third-party → local
- Always use explicit imports (`from x import y`)

## Type Hints

- Type hints required on all function signatures
- Use `X | None` syntax (Python 3.10+), not `Optional[X]`
- Use `list[X]` and `dict[K, V]`, not `List`/`Dict` from typing
- Use Pydantic `BaseModel` for API schemas and DTOs
- Use Pydantic `BaseSettings` for configuration classes

## Naming

- Variables/functions: `snake_case`
- Classes: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Private attributes: `_leading_underscore`

## FastAPI Patterns

- Use `APIRouter` for route organization with `prefix` and `tags`
- Use `Depends()` for dependency injection
- Annotate response models with Pydantic models
- Use async/await for I/O-bound operations
- Raise `HTTPException(status_code=..., detail="...")` for API errors

## Error Handling

- Use Pydantic validation errors for input validation
- Log errors with appropriate level before raising
- Never expose sensitive information in error messages

## Testing

- Fixtures in `conftest.py` with descriptive names
- Use `pytest.mark.anyio` for async tests
- Test both success and error cases
