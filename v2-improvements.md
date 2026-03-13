# v2 Improvements — External Review

An external review of the `feat/v2-minimal-refonte` branch identified concrete improvements. This document is the specification for applying them.

**Branch:** `feat/v2-minimal-refonte`
**Approach:** challenge each suggestion before applying — some may not survive scrutiny. The goal is a leaner, more effective forge, not blind application.

---

## 1. Skills-builder: add pre-draft filtering

**Problem:** the skills-builder has "Does Claude already do this by default? If yes, delete" in its audit checklist (point 3), but the checklist runs AFTER the draft is written. By then, confirmation bias makes it unlikely that Claude will delete content the user just dictated. The result: skills full of default behaviors presented as conventions (see python-conventions.md and react-conventions.md as evidence).

**Change:** in `skills/skills-builder/SKILL.md`, modify the Workflow section. Insert a filtering step between "Understand the need" and "Draft":

The new step should:
- Before drafting, list every instruction the user wants
- For each one, apply this test: "If I delete this line, does Claude's behavior actually change?" If no → it's noise, discard it and explain why to the user
- Show the user what was filtered and what survived, with reasoning
- Only then proceed to drafting with the surviving instructions

Also add a post-draft cross-reference step:
- After producing the draft, compare against all CLAUDE.md files in the layer hierarchy and existing skills
- Flag any redundancy or contradiction with existing instructions
- Propose merging or deleting if overlap is found

**Why this matters:** this is the single highest-leverage change. Every skill created through the builder will be leaner. The builder's own rules already say to do this — the fix is making it structurally unavoidable rather than a checklist item that gets skipped.

---

## 2. Eliminate python-conventions.md and react-conventions.md

**Problem:** these two `@context/` files (~105 lines combined) are loaded in every Atonra project session via `@` includes in `atonra/CLAUDE.md`. Most of their content is standard language conventions Claude follows by default:
- `snake_case` for Python, `camelCase` for JS — universal defaults
- `PascalCase` for classes — universal default
- `Use Depends() for dependency injection` — default FastAPI pattern
- `Fixtures in conftest.py` — default pytest pattern
- `Component composition over inheritance` — default React pattern
- `Use named imports` — default JS/TS behavior

This contradicts the project's own philosophy: "Only document what Claude gets wrong" and "YAGNI strict."

**Change:**
1. Delete `atonra/context/python-conventions.md`
2. Delete `atonra/context/react-conventions.md`
3. Remove their `@context/python-conventions.md` and `@context/react-conventions.md` imports from `atonra/CLAUDE.md`
4. Add the non-default tooling choices directly as directives in `atonra/CLAUDE.md`, under a new section. Only include what diverges from defaults. Approximate content:

```markdown
## Python Stack
- Package manager: uv (not pip). Linter/formatter: ruff (not black/flake8). Type checker: pyright. Tests: pytest.
- Line length: 119. Double quotes for strings. Use `X | None` syntax, not `Optional[X]`.

## React/TypeScript Stack
- Runtime + package manager: bun (not npm). Framework: React 19 + TanStack Start (file-based routing).
- Single quotes for strings. TypeScript strict mode. Zod for runtime validation.
```

**Challenge this:** verify that each line in the two context files is actually a default before deleting. If something is genuinely non-obvious or frequently gotten wrong by Claude, keep it. The test: run Claude on an Atonra Python project without the file and see if it uses `uv`, `ruff`, `119` line length, `double quotes` — it won't, because those are non-standard choices. Those lines stay. But `snake_case` and `conftest.py`? Claude does that without being told.

---

## 3. Expand supervised mode from 2 lines to 4-5 lines

**Problem:** the v1 `forge-master-memory.md` documents that supervised mode required 3 successive escalations because Claude kept violating it:
1. Basic rules → violated
2. Added "self-check before every action" → still violated
3. Added "Violation = stop" → current state

The v2 compresses all of this into two lines. This risks regression on the most problematic behavior in the project's history.

**Change:** in `CLAUDE.md`, expand the Supervised bullet from:

```
- **Supervised**: one action at a time. Execute, show result, wait for explicit approval before next action. Plan approval ≠ execution approval. When in doubt, ask. **Violation = stop.**
```

To approximately:

```
- **Supervised**: strict step-by-step mode. These rules override everything else:
  - One action, one pause. Execute a single action, show the result, STOP and wait for explicit approval.
  - Plan approval ≠ execution approval. Each step still requires individual validation before execution.
  - Never take unasked actions. If it seems like a logical next step, ASK instead of doing it.
  - **Violation = stop.** If you catch yourself about to chain actions or skip confirmation, STOP immediately, acknowledge the breach, and ask permission.
```

**Why not the full 9 rules from v1:** several were redundant ("ask before creating files" and "ask before running commands" are cases of "never take unasked actions"). 4 rules capture the essential behaviors without the token cost of 9.

**Challenge this:** maybe 2 lines is enough and the v1 violations were a compliance issue that more text won't fix. If so, the next step is a hook (see item 6), not more instructions. But given that the "Violation = stop" escalation did improve things in v1, keeping it prominent (not buried in a compressed line) is worth the ~3 extra lines.

---

## 4. Create LESSONS.md for institutional memory

**Problem:** the v1 had `forge-master-memory.md` which tracked behavioral fixes, escalation history, and architectural decisions. The v2 deleted it (YAGNI). But this knowledge is genuinely valuable: without it, there's no record that supervised mode was escalated 3 times, or that Claude tends to invent structures instead of mirroring references, or that Dagster business logic kept ending up in definitions.py.

The "Self-Improvement" instruction in CLAUDE.md tells Claude to propose improvements but creates no persistent artifact. After compaction or a new session, the lesson is lost.

**Change:**
1. Create `LESSONS.md` at the repo root (versioned in git, not gitignored)
2. Seed it with the key lessons from the deleted `forge-master-memory.md` (the behavioral fixes and their escalation history — this is valuable data)
3. Modify the Self-Improvement instruction in `CLAUDE.md` from:

```
When you notice a recurring behavioral gap or a pattern worth capturing, tell me and propose either a new instruction or a new skill. Do not silently adapt — make improvements explicit so they persist across sessions.
```

To:

```
When you notice a recurring behavioral gap or a pattern worth capturing, tell me and propose either a new instruction or a new skill. Do not silently adapt — make improvements explicit so they persist across sessions. When a fix is applied to any forge file, append a one-line entry to LESSONS.md: date, what changed, why the previous version failed.
```

**Keep it lightweight:** LESSONS.md is an append-only log, not a structured database. One line per lesson. Archive entries older than 6 months if it grows too long.

---

## 5. Split skills-builder into SKILL.md + companion files

**Problem:** the skills-builder is ~188 lines. About 80 of those are reference documentation (frontmatter fields, rules reference, skills content guidelines) that Claude only needs when creating a specific type of file. Loading all of it every time the skill activates wastes context.

**Change:** the skill already uses the directory format (`skills/skills-builder/SKILL.md`), so it can have companion files:

```
skills/skills-builder/
├── SKILL.md                ← workflow + principles + audit checklist (~110 lines)
├── skills-reference.md     ← frontmatter fields, dynamic context, content guidelines
├── rules-reference.md      ← .claude/rules/ location, path-specific rules, when to use
└── claude-md-reference.md  ← walk-up loading, @ imports, line targets
```

In SKILL.md, replace the detailed reference sections with pointers:
- "For skills frontmatter and content guidelines, see `${CLAUDE_SKILL_DIR}/skills-reference.md`"
- "For rules placement and path-scoping, see `${CLAUDE_SKILL_DIR}/rules-reference.md`"
- "For CLAUDE.md conventions and @ imports, see `${CLAUDE_SKILL_DIR}/claude-md-reference.md`"

Keep in SKILL.md: the workflow, placement decision tree, instruction writing principles, audit checklist, escalation path, and the post-modification commit guidance.

**Challenge this:** Claude may not reliably load companion files when needed. Test whether it actually reads them when referenced via `${CLAUDE_SKILL_DIR}`. If not, keep everything in SKILL.md — a long but functional skill is better than a short one that misses context.

---

## 6. Document the hook escalation trigger for supervised mode

**Problem:** the escalation path is clear (reword → "Violation = stop" → hook), and supervised mode is already at step 2. But there's no documented threshold for when to move to step 3. Without it, the natural tendency is to keep rewording (step 1) indefinitely.

**Change:** add to `ARCHITECTURE.md` in the Key Decisions table:

```
| **Supervised mode escalation** | Three escalations applied (v1). If supervised mode is violated 2+ times after v2 compression, create a PreToolUse hook that blocks action chaining when supervised mode is active. Do not reword instructions again — that approach has been exhausted. |
```

Also add to LESSONS.md (as seed content):

```
- 2026-03: Supervised mode required 3 instruction escalations in v1 (basic rules → self-check → Violation=stop). Next step is a hook, not more instructions.
```

**No code change needed now** — this is about documenting the decision boundary so it's not forgotten.

---

## 7. Improve setup.sh

**Problem:** setup.sh hardcodes "atonra" and has no safety mechanisms.

**Changes:**

### 7a. Parameterize company name
Replace hardcoded "atonra" references with a `--company` parameter (default: atonra). Approximately:

```bash
COMPANY="atonra"  # default

while [[ $# -gt 0 ]]; do
    case "$1" in
        --company)
            COMPANY="$2"
            shift 2
            ;;
        # ... existing args
    esac
done
```

Then use `$COMPANY` where `atonra` is currently hardcoded. Update the usage text.

### 7b. Add --dry-run
When `--dry-run` is passed, print what would be done without creating any symlinks. Modify `safe_link` to check a `DRY_RUN` flag and echo instead of executing.

### 7c. Add --verify
When `--verify` is passed, check all expected symlinks exist and point to real files. Report broken links. Exit with non-zero if anything is broken.

---

## 8. Move MCP naming convention to atonra/CLAUDE.md

**Problem:** the `mcp-setup` skill contains a naming convention (`{db}-{domain}-{infra}-{env}`) that is an Atonra-specific decision, not a generic best practice. The skill's own philosophy says "Skills = generic best practices. Company specifics go in CLAUDE.md files."

**Change:**
1. In `skills/mcp-setup/SKILL.md`, in the Naming section, replace the specific convention with:

```markdown
**When the user hasn't defined a naming convention yet**, propose one and let them choose.
Check the company or project CLAUDE.md for an existing convention before suggesting.
```

2. In `atonra/CLAUDE.md`, add under a relevant section:

```markdown
## MCP Naming
- Server names follow `{db}-{domain}-{infra}-{env}` pattern (e.g., `pg-financial-hetzner-test`).
- Same name used everywhere: MCP server key in ~/.claude.json, source ID in config file, config filename.
```

---

## 9. Add Design Review instruction to CLAUDE.md

**Problem:** Claude optimizes for task completion ("it works, tests pass, next step") but never pauses to evaluate design quality. No instruction forces a design self-review. The result: code that works but accumulates coupling, misplaced responsibilities, and structural debt.

**Change:** add a new section in `CLAUDE.md` after Problem-Solving:

```markdown
## Design Review
- After implementing a feature, review your own code BEFORE marking the step as done:
  1. Does each file have a single responsibility?
  2. Do dependencies flow inward? (domain never imports infrastructure)
  3. Could I swap the database/framework without touching business logic?
  4. Am I duplicating logic that should be shared, or abstracting something that only exists once?
- If any answer is no, refactor before moving on. Show what you changed and why.
```

**Why 4 questions, not 10:** these cover the most common design failures Claude makes. Adding more dilutes attention. The checklist should be fast enough that Claude applies it every time, not so long that it skips it.

**Challenge this:** does Claude actually self-review when instructed? Test on a real feature. If it skips the review consistently, this becomes a candidate for a hook (PostToolUse that runs a design linter) rather than an instruction.

---

## 10. Architecture structure standards as company skills

**Problem:** the user applies the same project structure for a given architecture + technology combination across all projects (e.g., all Python microservices use hexagonal architecture with the same folder layout). This is a company convention, not a project decision. Currently, there is nowhere in the forge to encode this — each project CLAUDE.md would have to repeat it.

Putting it in `atonra/CLAUDE.md` directly would bloat it (detailed folder trees + dependency rules). Putting it as `@context/` would load ALL structures in every session (a React project would load the Python microservice structure). The right mechanism is **skills** — they activate on demand based on description matching.

**Change:**

1. Create architecture structure skills in the company skills directory. These are created via `/skills-builder` following YAGNI — only create them when you actually start a project of that type. The first two would be:

   - `atonra/skills/python-microservice-structure.md` — activates when working on Python microservices
   - `atonra/skills/react-bff-structure.md` — activates when working on React BFF apps

2. Each skill should contain:
   - The canonical folder tree with purpose of each directory
   - Dependency rules (what imports what, what NEVER imports what)
   - Verification commands (e.g., `grep -r "from infrastructure" src/domain/` should return nothing)
   - A note that simplification is allowed (omit unnecessary layers) but dependency rules are non-negotiable

3. Add a short directive in `atonra/CLAUDE.md`:

```markdown
## Architecture Standards
- Python microservices follow hexagonal architecture — structure defined in the python-microservice-structure skill.
- React apps follow BFF pattern — structure defined in the react-bff-structure skill.
- Simplification is allowed (omit layers not needed) but dependency flow rules are non-negotiable.
```

**Example content for python-microservice-structure.md:**

```markdown
---
name: python-microservice-structure
description: "Hexagonal architecture structure for Python microservices — FastAPI, SQLAlchemy, Dagster"
---

# Python Microservice Structure

Standard layout for Atonra Python microservices. Simplify by omitting unnecessary layers, but never violate dependency rules.

## Canonical structure

    src/
    ├── domain/              ← pure business logic, zero external dependencies
    │   ├── models/          ← entities, value objects, domain exceptions
    │   └── ports/           ← abstract interfaces (repositories, external services)
    ├── application/         ← use cases, orchestration, DTOs
    │   └── services/        ← implements business workflows using domain ports
    ├── infrastructure/      ← adapters that implement domain ports
    │   ├── database/        ← SQLAlchemy models, repository implementations
    │   ├── http/            ← FastAPI routers, request/response serialization
    │   └── external/        ← third-party API clients
    └── tests/
        ├── unit/            ← domain + application tests (no I/O, no DB)
        └── integration/     ← infrastructure tests (real DB, real APIs)

## Dependency rules — NON-NEGOTIABLE

- domain/ NEVER imports from infrastructure/, application/, or any framework (SQLAlchemy, FastAPI, Pydantic).
- application/ imports from domain/ only (via ports). Never directly from infrastructure/.
- infrastructure/ implements ports defined in domain/. This is the only layer that imports frameworks.
- FastAPI routers call application services. Never domain models directly, never SQLAlchemy directly.

## Verification

After creating or modifying files, verify:
- `grep -rn "from infrastructure\|import sqlalchemy\|import fastapi" src/domain/` → must return nothing
- `grep -rn "from infrastructure" src/application/` → must return nothing
- Every new file is in the correct layer based on its responsibility

## When to simplify

- No external APIs? → omit infrastructure/external/
- Simple CRUD with no business logic? → omit application/services/, routers call repositories directly via ports
- Script or CLI tool? → flat structure is fine, this layout is for services
```

**Why skills, not @context:** skills auto-activate based on description keywords. When Claude works on a Python microservice, it loads the structure. When it works on a React app, it loads the React structure. Neither loads unnecessarily. The `@context/` mechanism would load all structures in every Atonra session.

**Why company skills, not global skills:** these encode Atonra's specific architectural choices (hexagonal with these exact layers, FastAPI+SQLAlchemy, etc.). Another company might use different patterns. Following the forge philosophy: "Skills = generic best practices. Company specifics go in company layer."

**Challenge this:** are these structures truly stable enough to encode? If you find yourself modifying the structure for every new project, it might be too rigid. The skill should describe the standard, not enforce it — Claude should ask before deviating, not be blocked from deviating.

---

## 11. Enriched plan format for autonomous execution

**Problem:** when Claude executes a plan autonomously, steps typically only have functional verification ("does it work?"). Design quality is never verified. A step like "Create User model → verify: it imports" produces any model that imports, regardless of architecture.

**Change:** this is a convention to document, not a file to create. Add to the skills-builder's knowledge (or to a future `/execute-plan` skill) the enriched plan format:

Each plan step should have:

```markdown
### Step N: <title>
- **Action:** what to implement
- **Design constraints:** architectural rules that apply (reference the structure skill if relevant)
- **Verify functional:** command that proves it works (e.g., `pytest tests/...`)
- **Verify design:** command or check that proves it's well-designed (e.g., `grep -rn "from infrastructure" src/domain/` returns nothing)
```

When the plan is created collaboratively (Phase 1), the human provides the design constraints. When Claude executes autonomously (Phase 2), it must pass BOTH verifications before marking a step as done.

**Example:**

```markdown
### Step 1: User domain model
- **Action:** create src/domain/models/user.py with User entity (id, email, hashed_password, created_at)
- **Design constraints:** pure domain — no SQLAlchemy, no Pydantic, no framework imports. Value objects for Email and HashedPassword.
- **Verify functional:** `python -c "from src.domain.models.user import User, Email; print('OK')"`
- **Verify design:** `grep -n "import sqlalchemy\|import pydantic\|from fastapi" src/domain/models/user.py` returns nothing

### Step 2: User repository port
- **Action:** create src/domain/ports/user_repository.py with abstract UserRepository interface
- **Design constraints:** abstract class only, no implementation details, methods return domain models
- **Verify functional:** `python -c "from src.domain.ports.user_repository import UserRepository; print('OK')"`
- **Verify design:** file contains only abstract methods, no concrete implementation
```

**This does NOT need to be a skill or file right now.** It's a practice to adopt when creating plans. Document it in ARCHITECTURE.md under a "Plan Format" section so it's not forgotten. Create a `/execute-plan` skill only when you actually start using this workflow — YAGNI.

**Challenge this:** is the dual verification too heavy for simple tasks? Probably yes. The enriched format is for features that touch architecture (new modules, new services). For bug fixes or small changes, a simple "fix X, verify with test Y" is enough. The plan format should say when to use which level.

---

## Order of execution

Apply in this order (each builds on the previous):

1. **Item 2** — delete context files, inline tooling in atonra/CLAUDE.md (smallest blast radius, immediate token savings)
2. **Item 3** — expand supervised mode (small CLAUDE.md edit)
3. **Item 9** — add Design Review instruction to CLAUDE.md (small edit, high impact)
4. **Item 4** — create LESSONS.md + update Self-Improvement instruction
5. **Item 8** — move MCP naming convention
6. **Item 10** — add architecture standards directive to atonra/CLAUDE.md (short directive only — create the actual structure skills later via /skills-builder when starting a real project, YAGNI)
7. **Item 7** — setup.sh improvements
8. **Item 1** — skills-builder pre-filtering (the biggest change, benefits from items 1-6 being done first)
9. **Item 5** — split skills-builder into companion files (do after item 8 so the final content is stable)
10. **Item 6** — document hook escalation trigger in ARCHITECTURE.md and LESSONS.md
11. **Item 11** — document enriched plan format in ARCHITECTURE.md (no code, just documentation)

After all changes, run the skills-builder's own audit checklist against every modified file to verify consistency.

---

## What this document is NOT

This is not a mandate. Each suggestion should be challenged:
- Does the problem described actually exist in practice?
- Is the proposed fix the simplest solution?
- Does it contradict another design decision?
- Is it YAGNI or genuinely needed?

If a suggestion doesn't survive scrutiny, document why in LESSONS.md and move on.
