# Architecture & Decisions

## Vision

claude-forge is a personal Claude Code configuration system. It separates concerns (behavior vs knowledge), optimizes token usage (lean CLAUDE.md + on-demand skills), maximizes compliance (audited instructions), and is reusable across projects and machines via symlinks.

## Philosophy

- **Claude + skills, not agents.** Agents are justified only for autonomy (background) or multi-agent collaboration. Skills cover everything else.
- **YAGNI strict.** Every file exists to answer a real need, not an anticipated one. Skills are created on demand when a pattern is observed, not pre-built.
- **Skills = generic best practices.** Community-level knowledge any team could use. Company/project specifics go in CLAUDE.md files.
- **Directives in CLAUDE.md, knowledge in skills.** CLAUDE.md says how to behave, skills teach domain expertise. `@` includes in CLAUDE.md provide factual context when no on-demand mechanism is available at the right scope.
- **Eat your own dog food.** The skills-builder is used to build and audit all forge files, including itself.

## Architecture

### Three-layer CLAUDE.md hierarchy

```
Layer 1 (Personal):   ~/.claude/CLAUDE.md              ← always loaded
Layer 2 (Company):    <workspace>/atonra/CLAUDE.md      ← company conventions + @context includes
Layer 3 (Project):    <project>/CLAUDE.md               ← project-specific, versioned in project repo
```

Layer 1 is a symlink to this repo. Layer 2 is a symlink to this repo's `atonra/` directory, deployed via `setup.sh --workspace`. Layer 3 is a standalone file in each project.

**Walk-up loading:** Claude Code walks up the directory tree loading every `CLAUDE.md` it finds. Running Claude in `~/dev/atonra/fundy/` loads all three layers. Only CLAUDE.md benefits from walk-up — rules and skills do not.

**`@` includes:** Layer 2 uses `@context/*.md` to load factual infrastructure context (database topology, pipeline patterns, stack conventions) without bloating the CLAUDE.md file itself.

### Skills activation

Skills live in `~/.claude/skills/` (symlinked from this repo). Claude auto-activates them based on the `description` field keyword matching. The skills-builder is the only skill shipped — others are created on demand.

### Deployment

`setup.sh` creates symlinks. No complex install, no profiles, no devcontainer. Linux first.

## Key Decisions

| Decision | Rationale |
|---|---|
| **Three layers with separation of concerns** | Layer 1 = personal preferences. Layer 2 = company directives + `@` includes for infrastructure context. Layer 3 = project-specific. Walk-up loading ensures all layers apply automatically to sub-projects. |
| **Layer 2 restored with `@` includes** | Originally removed (v2) as too rigid. Rediscovered the need during a DB audit: ~30 min lost on wrong infrastructure assumptions. Only CLAUDE.md walks up — rules and skills don't — so Layer 2 is the only mechanism scoped to all company projects that loads automatically. `@` includes separate directives from factual context. |
| **skills-builder, not forge-master agent** | An agent adds complexity (isolated context, tool restrictions) without benefit here. A skill that auto-activates when creating/reviewing instructions is simpler and sufficient. |
| **No hooks-builder** | Hooks are JSON config + shell commands. Claude already knows how to write those. The skills-builder has the hooks doc URL for reference if needed. |
| **No agent-builder (yet)** | YAGNI. The plan says "agents when skills aren't enough." The skills-builder placement table redirects to agents and can fetch the official docs when needed. |
| **SQL parameterized queries in global CLAUDE.md** | Technically belongs in a SQL/DB skill, but no such skill exists yet. Kept in CLAUDE.md as a security dealbreaker. Move to a skill when one is created. |
| **skills-builder description covers agents/hooks/rules** | Even though the skill doesn't detail agents/hooks, it knows how to redirect (placement table) and can fetch docs on demand (WebFetch mechanism). Narrowing the description would prevent activation when users ask "where should I put this instruction?" |
| **No pre-created skills** | Python, TypeScript, PostgreSQL, TimescaleDB, data-modeling, fintech, etc. were all removed. They are created via `/skills-builder` when the need appears in a real project. |
| **CLAUDE.md under 200 lines** | Official Anthropic recommendation. Longer files reduce adherence. Reference material goes in skills (on-demand) or `.claude/rules/` (path-scoped). |
| **WebFetch for doc alignment** | Skills-builder embeds essential best practices but proposes fetching official docs before creating/updating skills. Handles staleness without bloating the skill. |
| **Feedback integrated, not separate** | No `/flag` or `/review-flags`. Self-improvement instruction in CLAUDE.md: Claude proposes new instructions or skills when it notices recurring gaps. Direct correction in conversation. |
| **No auto-commit** | Claude informs that forge files changed, proposes a Conventional Commits message, waits for user confirmation. |

## What Was Removed (and Why)

| Removed | Reason |
|---|---|
| `agents/forge-master.md` | Replaced by skills-builder skill |
| `feedback/`, `/flag`, `/review-flags` | Over-engineered. Self-improvement instruction + direct correction is sufficient |
| `memory/forge-master-memory.md` | Agent memory no longer needed. Auto memory (native Claude Code) handles per-project learnings |
| `skills/instruction-writing/` | Content absorbed into skills-builder |
| `skills/postgresql.md` | Created on demand when needed |
| `atonra/skills/*.md` (7 files) | Created on demand when needed |
| `atonra/agents/data-engineer.md` | YAGNI — agents when skills aren't enough |
| `.devcontainer/` | YAGNI — revisit when the need is confirmed |
| `install.sh` | Over-engineered (profiles, devcontainer init). Replaced by simple `setup.sh` |
| `DECISIONS.md` | Replaced by this file |
| `changelog/` | YAGNI |

## Deferred (YAGNI)

Revisit when the need is real:

- **Technical skills** (postgresql.md, timescaledb.md, etc.) → create via `/skills-builder` when working on a project that needs them
- **Agent-builder** → when `context: fork` in skills isn't enough and a real agent is needed
- **setup.ps1** (Windows) → when the user changes machine
- **Devcontainer** → when portability beyond symlinks is needed

## Reload Behavior

- **CLAUDE.md changes** take effect after `/compact` (re-reads from disk)
- **Skill changes** require a new session
- **SESSION.md + auto memory** preserve context across sessions
