# Frontend checklist

Reference: `react-conventions.md` (bun, React 19, TanStack Start/Query, server functions, Zod). Judge against sibling routes/components first (SKILL.md Step 3).

## Structure & separation of concerns

- Components render; data fetching lives in TanStack Query hooks; backend calls go through server functions (TanStack Start), never direct fetches from components to internal services.
- Business/formatting logic extracted into pure functions (testable without rendering), not inlined in JSX.
- One component = one responsibility; a component mixing fetching, transformation, and layout of several concerns → split.
- No duplicated component/hook when an equivalent exists in the codebase (search before accepting).

## Data contract

- Every response crossing a boundary is validated with Zod; the schema matches the API contract (field names, nullability, units — e.g. market cap absolute vs millions, price major vs minor unit).
- Frontend never recomputes a value the backend owns (e.g. price from market cap / shares).
- Nullable/missing data is rendered explicitly, not as `0` or `NaN`.

## State & effects

- Server state in TanStack Query (keys stable and complete — include every param that changes the result); no copying query data into local state.
- `useEffect` only for real side effects; derived values computed during render.
- No mutable module-level state.

## Security & auth

- BFF pattern: no token read/stored in frontend JS (HTTP-only cookies only); no secrets or internal URLs hardcoded.
- No `dangerouslySetInnerHTML` on untrusted content.

## Quality

- TypeScript strict: no `any`, no non-null assertions hiding real nullability.
- Errors surfaced to the user and logged to Sentry; no swallowed promise rejections.
- Tests with `bun test` + `@testing-library/react` for new logic and interactive components.
