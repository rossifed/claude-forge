# React / TypeScript Conventions

Non-default choices only — Claude handles standard React/TypeScript conventions by default.

## Tooling

- Runtime + package manager: `bun` (not npm/yarn)
- Framework: React 19, TanStack Start with file-based routing (not Next.js/React Router)
- Data fetching: TanStack Query
- Backend calls: server functions (TanStack Start pattern)
- Runtime validation: Zod

## Testing

- Use `bun test` with `bun:test` (not jest)
- Use `@testing-library/react` for component tests

## Observability

- Log errors to Sentry
