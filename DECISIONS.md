# Decisions

Rationale behind key choices in this configuration. Update when decisions change.

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

## Instruction formulation follows Anthropic best practices
Documented in skills/instruction-writing/SKILL.md (symlinked to ~/.claude/skills/).
Key rules: NEVER needs an alternative, emphasis only for dealbreakers,
only document what Claude gets wrong, keep instructions minimal.