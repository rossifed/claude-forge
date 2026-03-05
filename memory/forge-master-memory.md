Forge Master Memory
This file is maintained by the forge-master agent. Do not edit manually unless correcting an error.

## User patterns
- Works at Atonra, a fintech company focused on portfolio optimization.
- Company has a project called "Fundy" — microservices architecture with Python (FastAPI, Dagster, dbt, ClickHouse, PostgreSQL) and React (TanStack Start, Bun, TypeScript).
- Has a colleague who wrote Copilot instructions that need conversion to Claude Code format.
- Interested in layered instruction architecture: personal CLAUDE.md -> company atonra_claude.md -> project CLAUDE.md.
- Prefers explicit tradeoff analysis before decisions.
- Cares about not duplicating instructions across layers.

## Instruction lessons
- Copilot instruction files tend to include default behaviors as instructions (type hints, naming conventions, async/await). These are noise for Claude Code.
- When reviewing instructions ported from other AI tools, audit every line against "does Claude already do this by default?"
- Company-wide files should focus on: tooling decisions (uv vs pip, bun vs npm), architectural mandates (microservices boundaries, BFF), domain-specific rules (financial data types, currency codes).
- Repository structure sections go stale quickly. Keep them minimal or project-specific only.

## Behavioral fixes applied
- Supervised mode: user reports Claude still chains actions despite protocol. Added "self-check before every action" rule as a concrete internal verification step. If this still fails, next escalation is a hook.
- Supervised mode escalation (2026-03-05): self-check alone insufficient. Added "Violation = stop" rule requiring Claude to halt, acknowledge the near-violation, and ask permission. This is the last instruction-level escalation before moving to hooks.
- Dagster code structure: user reports Claude puts business logic in definitions.py. Added explicit Dagster Code Structure subsection to atonra_claude.md under Data / Orchestration.
- Reference project fidelity: user reports Claude invents different structures instead of mirroring references. Added Reference Projects subsection to personal CLAUDE.md under Code Principles.
- Premature implementation (2026-03-05): Claude jumps to implementation details before understanding the problem, and over-scopes when asked to brainstorm. Added "Problem-Solving Approach" section with 4 rules: analyze before asking, start minimal, do the work (don't delegate back), debug with a hypothesis.
- Delegating work back (2026-03-05): Claude says "don't forget to update X" instead of making the change. Addressed by "Do the work, do not delegate it back" instruction.
- Blind debugging (2026-03-05): Claude retries same failed approach on errors without diagnosing root cause. Addressed by "Debug with a hypothesis" instruction.

## Review history
- 2026-03-04: Reviewed Fundy CLAUDE.md (originally Copilot instructions). Identified 8 WARNING-level issues (noise/defaults/vagueness), 1 CRITICAL (wrong target tool), 2 INFO. Proposed company-wide atonra_claude.md with three approaches (A: thin company/fat project, B: company+skills, C: self-contained). Recommended starting with C, migrating to B. Drafted both company-wide and project-specific files. Awaiting user decisions on approach, file location, and accuracy of inferred conventions.
- 2026-03-04: Applied behavioral fixes for 3 recurring issues (supervised mode chaining, Dagster code coupling, reference pattern divergence). Edits placed in personal CLAUDE.md (issues 1 & 3) and atonra_claude.md (issue 2).
- 2026-03-05: Batch behavioral fix from 8 complaints. 4 were already covered by supervised mode (compliance failures, not missing instructions). Added "Violation = stop" as escalation. 4 were new behaviors: added Problem-Solving Approach section (analyze before asking, start minimal, do the work, debug with hypothesis). Modified Communication section to cross-reference and avoid contradictions. Next escalation path for supervised mode: hooks.