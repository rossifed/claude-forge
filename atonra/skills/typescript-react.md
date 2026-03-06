---
description: "TypeScript/React conventions for Atonra: bun, TanStack Start, Zod, Vitest. Auto-activates for TypeScript codebases."
---

# TypeScript / React Conventions

## Tooling

- **Runtime + package manager:** `bun` (never npm/yarn/pnpm)
- **Framework:** React with TanStack Start (file-based routing, server functions)
- **Data fetching:** TanStack Query
- **Runtime validation:** Zod
- **Linter:** ESLint (TanStack config)
- **Formatter:** Prettier (single quotes)

## Style Decisions (non-default)

- Quotes: single quotes (Prettier)
- `interface` for object shapes, `type` for unions and primitives
- Path aliases: `@/components/...`, `@/util/...`
- CSS class names: `kebab-case`
- Avoid type assertions (`as Type`) unless justified with a comment
- Never add `@ts-ignore` or `any` without a justifying comment

## Commands

- **Install:** `bun install`
- **Dev server:** `bun run dev`
- **Build:** `bun run build`
- **Lint:** `bun run lint`
- **Test:** `bun test` or `bun test path/to/test.ts`

## Testing

- Vitest with `@testing-library/react` and Happy DOM
- Mock external API calls in tests.
