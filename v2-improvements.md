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

## Order of execution

Apply in this order (each builds on the previous):

1. **Item 2** — delete context files, inline tooling in atonra/CLAUDE.md (smallest blast radius, immediate token savings)
2. **Item 3** — expand supervised mode (small CLAUDE.md edit)
3. **Item 4** — create LESSONS.md + update Self-Improvement instruction
4. **Item 8** — move MCP naming convention
5. **Item 7** — setup.sh improvements
6. **Item 1** — skills-builder pre-filtering (the biggest change, benefits from items 2-4 being done first)
7. **Item 5** — split skills-builder into companion files (do after item 6 so the final content is stable)
8. **Item 6** — document hook escalation trigger in ARCHITECTURE.md and LESSONS.md

After all changes, run the skills-builder's own audit checklist against every modified file to verify consistency.

---

## What this document is NOT

This is not a mandate. Each suggestion should be challenged:
- Does the problem described actually exist in practice?
- Is the proposed fix the simplest solution?
- Does it contradict another design decision?
- Is it YAGNI or genuinely needed?

If a suggestion doesn't survive scrutiny, document why in LESSONS.md and move on.
