# Changelog

## 2026-03-05 — Extract Atonra CLAUDE.md into Composable Skills

### Motivation

The `companies/atonra/CLAUDE.md` was 133 lines mixing company-wide mandates (~30%)
with technology-specific conventions (~70%). This caused two problems:

1. **Unnecessary context loading.** A data pipeline project loaded FastAPI and React
   rules it would never use. A React frontend loaded Dagster and SQLAlchemy rules.
   Every project paid the context budget cost of all tech stacks.

2. **Violated the forge's own principle.** The DECISIONS.md states "all tech-specific
   content in skills, never in CLAUDE.md." The Atonra company file was breaking this
   rule — Python conventions, TypeScript patterns, and Dagster structure were inline
   instead of being skills.

### Approach

**Open/Closed decomposition:** the company CLAUDE.md stays thin and immutable
(company mandates only), while technology conventions become composable skills that
auto-activate based on project context via description matching.

- No manual skill selection needed for day-to-day work — Claude Code auto-triggers
  skills when editing relevant file types.
- A scaffold skill (`/scaffold`) handles one-time project bootstrapping with an
  interactive flow.
- The `install.sh` skill loop was extended to support directory-based skills
  (needed for scaffold's `SKILL.md` format).

### Changes

| File | Action | Before | After |
|---|---|---|---|
| `companies/atonra/CLAUDE.md` | Rewritten | 133 lines (all-in-one) | 47 lines (mandates only) |
| `companies/atonra/skills/python.md` | Created | — | 50 lines |
| `companies/atonra/skills/typescript-react.md` | Created | — | 36 lines |
| `companies/atonra/skills/data-orchestration.md` | Created | — | 19 lines |
| `companies/atonra/skills/scaffold/SKILL.md` | Created | — | 138 lines |
| `install.sh` | Updated | file-based skills only | + directory-based skills |
| `DECISIONS.md` | Updated | — | +2 entries (extraction rationale, scaffold format) |
| `README.md` | Updated | generic atonra listing | detailed skill tree |

### What stayed in CLAUDE.md (company mandates)

Architecture, Git hooks, Secrets (SOPS/direnv), CI/CD, Observability, Dev Environment.

### What moved to skills

| Skill | Content | Auto-triggers on |
|---|---|---|
| `python.md` | uv, ruff, pyright, FastAPI, SQLAlchemy, pytest, Pydantic BaseSettings | Python codebases |
| `typescript-react.md` | bun, TanStack Start, Zod, Vitest, Prettier | TypeScript codebases |
| `data-orchestration.md` | Dagster structure, dbt layering, ClickHouse, Cognito | Pipeline codebases |
| `scaffold/SKILL.md` | Interactive project bootstrapping | Explicit `/scaffold` only |

### Context budget impact

Total skill descriptions: ~730 chars + YAML overhead ~300 chars = ~1KB out of 16KB budget.
No concern — well within limits.

---

## 2026-03-05 — Behavioral Feedback Loop

### Motivation

Improving Claude's behavior was a manual loop: notice problem in project → switch to
forge → explain from memory → forge-master fixes instructions. This loses context
(Claude in-session knows what happened, but that's gone once you switch projects),
has no structure (free-form complaints), and no pattern detection.

### Approach

Two-phase system modeled on instruction-level RLHF:

1. **Capture** (`/flag`): global skill invoked mid-session from any project. Claude
   structures the feedback using conversation context it already has. Writes a
   standardized incident report to `feedback/`.

2. **Process** (`/review-flags`): periodic skill invoked from forge project. Reads
   accumulated flags, groups by category, cross-references existing instructions,
   proposes changes.

### Changes

| File | Action |
|---|---|
| `skills/flag/SKILL.md` | Created — structured feedback capture |
| `skills/review-flags/SKILL.md` | Created — batch flag processing |
| `feedback/.gitkeep` | Created — feedback storage directory |
| `feedback/processed/.gitkeep` | Created — processed flags archive |
| `DECISIONS.md` | Added feedback loop rationale |
| `README.md` | Added Feedback Loop section |

### Escalation path

Instruction fix → "Violation = stop" pattern → hook (programmatic enforcement).
If 3+ flags share a category, the issue likely needs a hook, not more instructions.
