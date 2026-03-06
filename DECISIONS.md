# Decisions

Rationale behind key choices in this configuration. Update when decisions change.

## Company profiles are pluggable, not hardcoded
The forge is company-agnostic. Company conventions live in `<name>/CLAUDE.md` at the repo
root (e.g., `atonra/`). Deployed via `install.sh --company <name> --workspace <dir>` which
symlinks the company CLAUDE.md to the workspace root. Claude Code walks up directories, so
all projects under that workspace inherit company conventions automatically. Open/Closed
principle: the company file is closed for modification, projects extend via their own CLAUDE.md.
Company-specific skills live in `<name>/skills/` and agents in `<name>/agents/`, both
symlinked into the global directories at install time.

## Three-layer CLAUDE.md hierarchy
Layer 1 (Personal): `~/.claude/CLAUDE.md` — tech-agnostic preferences, loaded everywhere.
Layer 2 (Company): `<workspace>/CLAUDE.md` — tech stack and conventions, loaded for all
projects under that workspace. Layer 3 (Project): `<project>/CLAUDE.md` — project-specific
directives. Claude Code merges all layers automatically via directory walking.

## CLAUDE.md kept under ~35 real instructions (~50 lines with headers/spacing)
Claude Code system prompt uses ~50 instructions. LLMs follow ~150-200 instructions reliably.
Keeping CLAUDE.md short ensures every instruction gets attention.
All detailed conventions go in skills, not in CLAUDE.md.

## Two work modes only (Autonomous / Supervised)
Three modes had ambiguous boundaries. Two extremes are clearer.
Autonomous = no permission, no explanation. Supervised = show, explain, wait for validation.

## SESSION.md for context persistence across compactions
Compaction rules alone are advisory — Claude can ignore them.
A file on disk survives context compression. Claude re-reads it after compaction.
SESSION.md MUST be in .gitignore (temporary, session-scoped).

## All tech-specific content in skills, never in CLAUDE.md
CLAUDE.md is language-agnostic and framework-agnostic.
Python conventions, FastAPI patterns, DDD architecture — all in skills.
Same CLAUDE.md works regardless of project language or framework.

## Skills are global, not tied to agents
Any agent or Claude itself can load any skill when relevant.
Skills live in skills/, agents live in agents/. No nesting.

## Agent memory stored in memory/ directory
Named after the agent with -memory suffix (memory/forge-master-memory.md).
Versioned in git for portability across machines.
Agent fills it over time — starts empty.
Not using built-in memory: user because it is not portable.

## forge-master is a tool, not an automatic rule
No instruction in CLAUDE.md to auto-delegate to forge-master.
User decides when to call it. CLAUDE.md must work independently.

## Conventional Commits as default
Used by default unless project-specific conventions override.
Reduces decision fatigue on new projects.

## Docker by default with exceptions
Dockerize everything except quick scripts and early POCs.
Not a hard rule — context matters.

## Never hardcode anything
Broader than just secrets. No magic numbers, no config values in code.
Everything in config files or environment variables.

## Company CLAUDE.md contains mandates only, tech conventions are skills
The Atonra CLAUDE.md mixed company-wide mandates (~30%) with technology-specific
conventions (~70%). A data pipeline project loaded FastAPI rules, and vice versa.
Extracted Python, TypeScript/React, and Data/Orchestration into separate skills that
auto-activate based on project context. The company CLAUDE.md stays thin (~40 lines)
and immutable — it only contains architecture, git, secrets, CI/CD, observability, and
dev environment mandates that apply to every project regardless of tech stack.
Granularity: one skill per tech stack (python, typescript-react, data-orchestration),
not per tool (no separate ruff.md, pytest.md). Tools are too fine-grained for a
company with a standardized stack.

## Scaffold skill uses directory format with disable-model-invocation
The scaffold skill is directory-based (`scaffold/SKILL.md`) to allow future template
files alongside the skill instructions. It uses `disable-model-invocation: true` so it
never auto-triggers — project scaffolding should only happen when explicitly requested
via `/scaffold`. It generates a project CLAUDE.md that references skills by description,
never duplicating their content.

## Behavioral feedback captured via /flag skill, processed via /review-flags
The manual workflow (notice problem → switch to forge → explain → fix) loses context
and doesn't scale. The `/flag` skill captures structured incident reports in-context
(where Claude has full session context of what went wrong) and writes them to
`feedback/`. The `/review-flags` skill processes accumulated flags into instruction
changes. Skill-based (not hook-based) because Claude needs to help structure the
feedback — a hook can only log raw text. The escalation path for compliance failures
is: reword instruction → add "Violation = stop" pattern → hook (programmatic).

## Instruction formulation follows Anthropic best practices
Documented in skills/instruction-writing/SKILL.md (symlinked to ~/.claude/skills/).
Key rules: NEVER needs an alternative, emphasis only for dealbreakers,
only document what Claude gets wrong, keep instructions minimal.