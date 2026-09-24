# Python checklist

Applies to service code, Dagster asset/loader code, scripts. Judge against the project's sibling files first (SKILL.md Step 3), then these principles.

## Functional core, imperative shell

- **Pure vs impure is visible.** Logic that can be pure (parsing, transformation, validation, computation, SQL/query *building*, row assembly) is a function `input → output` with no IO, no hidden state, no clock/random/env reads. IO (DB, HTTP, filesystem, Dagster context, logging of results) sits in a thin outer layer that calls the pure core.
  - Finding example: a function that fetches rows, filters them, and writes the result → split into `fetch` (impure) / `select_rows(rows) -> rows` (pure, unit-tested) / `write` (impure).
- **Small functions, one responsibility.** A function needing a comment to explain *what* it does, or mixing abstraction levels (business rule + SQL string + retry loop), should be split. Flag functions ruff C90 would pass but that still do several things.
- **Immutability.** Config/value objects are frozen (`@dataclass(frozen=True)`, Pydantic `frozen`); no mutation of arguments; no module-level mutable state.
- **Thread-safety by construction.** No shared mutable state across workers/threads; per-worker resources (one session/connection per worker). A shared object "that happens to be thread-safe" is a finding — remove the question.

## Design principles

- **SOLID**
  - SRP: one reason to change per class/module.
  - OCP: adding a new variant (provider, entity class, loader mode) adds a module/registration, not an `if/elif` in existing code.
  - LSP: subclasses/implementations honor the base contract (no raising `NotImplementedError` on half the interface).
  - ISP: consumers do not depend on methods they don't use.
  - DIP: domain logic depends on abstractions/parameters, not on concrete clients created inside it (inject the resource).
- **DRY** — search for existing helpers before accepting a new one (Step 5 of SKILL.md). Two near-identical blocks in the diff = extract.
- **KISS** — no speculative abstraction (a base class / factory / plugin system with one implementation), no clever construct where an explicit one reads better.
- **DDD** — domain vocabulary is consistent with the data model and business (same name for the same concept across API, service, DB); domain rules live in the domain/service layer, not in routes or schemas; boundaries between services respected (no cross-service imports — HTTP only).
- **Clean code** — explicit names (`company_currency`, not `cmp_ccy`); no dead code, commented-out code, or unused parameters; comments explain *why*, never *what*; early returns over deep nesting.

## Correctness & robustness

- Errors: no bare `except`/`except Exception: pass`; errors caught only where they can be handled; failure is loud (a pipeline step that swallows an error and reports success is a 🔴).
- Types: annotations on public functions; no `Any` where a type is known; Pydantic models at IO boundaries.
- Resources: DB connections/sessions/files closed (context managers); no connection opened per row.
- Logging: structured (JSON), no sensitive data, no `print`.

## Tests

- Every new pure function and every changed behavior has a unit test in the project's existing test layout and style (mirror a sibling test file).
- Non-trivial logic covered on its edges: empty input, nulls, duplicates, boundary dates, the guard paths.
- Tests exercise the pure core without mocking half the world; heavy mocking signals missing pure/impure separation.
- Async tests follow the project convention (`pytest.mark.anyio`).
- Integration tests needing DB are marked (`@pytest.mark.integration`) per project config.
