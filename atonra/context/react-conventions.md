# React / TypeScript Conventions

## Tooling

- Runtime + package manager: `bun`
- Linter: `eslint`
- Formatter: `prettier`
- Framework: React 19, TanStack Start (file-based routing)

## Formatting

- Single quotes for strings
- TypeScript strict mode enabled

## Type System

- Avoid `any` — use `unknown` when type is uncertain
- Use `interface` for object types, `type` for unions/primitives
- Use Zod for runtime validation
- Avoid type assertions (`as Type`) when possible

## Naming

- Variables/functions: `camelCase`
- Components/classes: `PascalCase`
- Constants: `UPPER_SNAKE_CASE` or `kebab-case` for CSS
- Hooks: `use` prefix (`useAuth`, `useQuery`)

## Imports

- Use path aliases: `@/components/...`, `@/util/...`
- Group imports: React → external → internal
- Use named imports for modules

## React Patterns

- TanStack Start file-based routing
- Server functions for backend calls
- TanStack Query for data fetching
- Component composition over inheritance

## Error Handling

- Use error boundaries for component errors
- Handle async errors in server functions
- Display user-friendly error messages
- Log errors to Sentry

## Testing

- Use `bun test` with `bun:test`
- Use `@testing-library/react` for component tests
- Mock external API calls
- Test component rendering and interactions
