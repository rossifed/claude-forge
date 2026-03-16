---
name: skills-builder
description: "Create, review, or improve Claude Code skills, instructions, CLAUDE.md files, agents, hooks, or rules"
user-invocable: true
argument-hint: "what to build or review"
---

# Skills Builder

Build and audit Claude Code configuration files: skills, CLAUDE.md files, agents, hooks, and rules.

## Official references

- Memory, CLAUDE.md & rules: https://code.claude.com/docs/en/memory
- Skills: https://code.claude.com/docs/en/skills
- Best practices: https://code.claude.com/docs/en/best-practices
- Hooks: https://code.claude.com/docs/en/hooks-guide
- Prompt engineering: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview

### When to consult official docs

- **Before creating or updating a skill:** propose to the user: "Want me to check the latest official docs first? → `WebFetch https://code.claude.com/docs/en/skills`". Do not fetch without approval.
- **On doubt about facts:** if unsure about a frontmatter field, syntax, or whether a capability exists, say so and propose the specific WebFetch command. Never guess.
- **On explicit request:** when the user asks to check or align with official docs, fetch the relevant URL above.
- **On divergence:** if a fetched doc contradicts these instructions on a factual point (field name, syntax, feature existence), flag it: show both versions and ask whether to update. Differences in opinion or style are not divergences — only mention them if relevant.

## Workflow

1. **Understand the need.** Ask what behavior the user wants. Use the placement decision tree to identify where it belongs.
2. **Propose alignment check.** Offer to fetch official docs before drafting (see "When to consult official docs").
3. **Filter before drafting.** List every instruction you plan to include. For each, ask: "If I delete this, does Claude's behavior change?" Remove non-differentiating content. Cross-reference against existing CLAUDE.md hierarchy and skills to flag redundancy. Show the user what was filtered out and why.
4. **Draft.** Write the content following the principles below, using only the surviving instructions.
5. **Validate frontmatter.** Check: `name` is lowercase/hyphens/max 64 chars, `description` is present, boolean fields use `true`/`false` (not strings), no unknown fields.
6. **Validate content.** Run the audit checklist against every instruction. Check line count (flag at 400+).
7. **Verify.** Re-read the full file, confirm each instruction passes all 8 checklist points. Suggest the user test activation: "Ask Claude 'What skills are available?' to verify it appears."

## Placement decision tree

| Signal | Place it in |
|---|---|
| Personal preference, always applies | `~/.claude/CLAUDE.md` |
| Company convention, all company projects | `<workspace>/company/CLAUDE.md` |
| Project-specific directive | Project's own `CLAUDE.md` |
| Language/framework/tool knowledge | Skill (auto-activated by `description`) |
| Applies only to specific file patterns | `.claude/rules/*.md` with `paths` frontmatter |
| Repeatable workflow triggered by user | Skill with `user-invocable: true` |
| Task needing isolated context or parallel execution | Agent |
| Zero-tolerance rule consistently violated | Hook |

## Instruction writing principles

- **Specific and actionable.** Bad: "write clean code." Good: "functions must have a single responsibility — if it needs a comment to explain what it does, rename or split it."
- **NEVER without alternative.** Bad: "NEVER use float." Good: "NEVER use float for monetary values — use Decimal with explicit precision."
- **Emphasis is scarce.** Reserve NEVER, ALWAYS, NON-NEGOTIABLE for true dealbreakers. Bad: every rule has ALWAYS. Good: 2-3 emphasized rules in a 30-line file.
- **Only document gaps.** If Claude already does it by default, delete. Bad: "respond helpfully to user questions." Good: "challenge my suggestions before agreeing — evaluate alternatives first."
- **One instruction = one behavior.** Bad: "use TypeScript and always add tests." Good: two separate instructions.
- **No contradictions.** If two instructions conflict, resolve or delete one.
- **Golden path over constraints.** Bad: "don't do A, B, or C." Good: "Do X, then Y, then Z."
- **Verification criteria.** Bad: "write good tests." Good: "after writing tests, run `pytest` and verify zero failures."
- **Examples over abstractions.** When a principle could be misinterpreted, add one concrete example inline.
- **Lean context.** Every instruction competes for attention. Fewer, stronger instructions win.

## CLAUDE.md reference

- Target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence.
- Move reference material to skills (on-demand) or `.claude/rules/` files (path-scoped).
- CLAUDE.md changes take effect after `/compact` (re-reads from disk). No new session needed.
- **Walk-up loading:** CLAUDE.md files are loaded by walking up the directory tree from the working directory. Running Claude in `foo/bar/` loads both `foo/bar/CLAUDE.md` and `foo/CLAUDE.md`. Subdirectory CLAUDE.md files load on demand when Claude reads files in those directories.
- **`@` imports:** `@path/to/file.md` syntax expands and loads the referenced file into context at launch. Relative paths resolve relative to the file containing the import. Max 5 levels of nesting. First encounter in a project shows an approval dialog.

## Rules reference

Rules are markdown files in `.claude/rules/` that keep instructions modular. They can be scoped to specific file patterns.

### Location and loading

| Location | Scope | Loaded |
|---|---|---|
| `<project>/.claude/rules/*.md` | Project, shared via git | At launch (or on file match if `paths:` set) |
| `~/.claude/rules/*.md` | User, all projects | At launch (before project rules) |

- Rules are discovered recursively — subdirectories like `frontend/` or `backend/` are supported.
- Rules **do not walk up** the directory tree — unlike CLAUDE.md, they are scoped to their project.
- Symlinks are supported for cross-project sharing: `ln -s ~/shared-rules .claude/rules/shared`.

### Path-specific rules

Use `paths` frontmatter to load rules only when Claude works with matching files:

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "**/*.sql"
---
```

Rules without `paths` frontmatter load unconditionally at launch.

### When to use rules vs other mechanisms

| Need | Use |
|---|---|
| Instructions scoped to file patterns | `.claude/rules/` with `paths` frontmatter |
| Factual context shared across projects | `@` import in a walk-up CLAUDE.md |
| On-demand domain knowledge | Skill |
| Permanent directive for all company projects | Company CLAUDE.md (walk-up layer) |
| Enforcement with zero tolerance | Hook |

## Skills reference

**Single file:** `skills/my-skill.md` — simple, self-contained.
**Directory:** `skills/my-skill/SKILL.md` — allows companion files alongside:

```
my-skill/
├── SKILL.md           # Main instructions (required)
├── reference.md       # Detailed docs (loaded when needed)
├── examples/          # Example outputs
└── scripts/           # Scripts Claude can execute
```

Reference supporting files from SKILL.md so Claude knows when to load them.

### Frontmatter fields

All fields are optional. Only `description` is recommended.

| Field | Description |
|---|---|
| `name` | Display name and `/command`. Lowercase, numbers, hyphens only, max 64 chars. Defaults to directory name. |
| `description` | What the skill does and when to use it. Claude uses this to decide auto-activation. |
| `argument-hint` | Hint shown during autocomplete (e.g., `[issue-number]`). |
| `disable-model-invocation` | `true` to prevent Claude from auto-loading. User-only via `/name`. Default: `false`. |
| `user-invocable` | `false` to hide from `/` menu (background knowledge only). Default: `true`. |
| `allowed-tools` | Tools Claude can use without permission when skill is active. Inline (`Read, Grep, Glob`) or YAML list. |
| `model` | Model override when skill is active. |
| `context` | `fork` to run in an isolated subagent context. |
| `agent` | Which subagent type to use when `context: fork` is set (e.g., `Explore`, `Plan`, or custom agent). |
| `hooks` | Hooks scoped to this skill's lifecycle (see hooks docs). |

### Dynamic context

- `$ARGUMENTS` — all arguments passed when invoking. `$ARGUMENTS[0]`, `$ARGUMENTS[1]` or shorthand `$0`, `$1` for positional access.
- `${CLAUDE_SKILL_DIR}` — resolves to the skill's directory path.
- `${CLAUDE_SESSION_ID}` — current session ID (useful for logging or session-specific files).
- `!command` — shell command whose stdout is injected at load time (preprocessing, not executed by Claude).

## Skills content guidelines

- **Generic and community-driven.** Best practices any team could use. Company-specific conventions go in company CLAUDE.md, not skills.
- **Self-contained.** A skill must make sense without other skills loaded.
- **Description drives activation.** Write the `description` with keywords that trigger auto-loading. Be specific enough to avoid false activation.
- **Description budget.** All skill descriptions share 2% of the context window (fallback: 16k chars). Keep descriptions concise.
- **Structured for scanning.** Headers, tables, short bullets. Claude processes structured content faster than prose.
- **Right-sized.** Keep SKILL.md under 500 lines. Move detailed reference material to supporting files.
- **Split when needed.** If a skill covers multiple distinct domains, propose splitting into focused skills. Split only when size causes a real problem — not preemptively.
- **Line count check.** When creating or updating a skill, check the line count. If it exceeds 400 lines, flag it and propose options (split, move content to supporting files, or keep as-is with justification).

## Audit checklist

Apply to every instruction before finalizing:

1. Is it specific and actionable?
2. Does a NEVER include its alternative?
3. Does Claude already do this by default? If yes, delete.
4. Is it redundant with another instruction? If yes, merge or delete.
5. Is emphasis justified for this specific rule?
6. Is it in the right place (CLAUDE.md vs skill vs agent vs hook vs rules)?
7. Does it contradict another instruction?
8. Does it include verification criteria where applicable?

**Self-check:** after writing all instructions, re-read the full file and run each line through points 1-8. Fix before presenting to the user.

## Escalation path

When a behavioral problem persists despite instructions:

1. **Reword** the instruction to be more specific and actionable.
2. **Add "Violation = stop" pattern** — explicit instruction to halt and ask when about to violate.
3. **Create a hook** — programmatic enforcement with zero tolerance.

## After creating or modifying forge files

When you create or modify any file in the claude-forge repository (skills, CLAUDE.md, agents, hooks):
- Inform the user that forge files were changed.
- Propose a commit message following Conventional Commits format.
- Do NOT auto-commit — wait for user confirmation.
- **Reload guidance:** CLAUDE.md changes take effect after `/compact`. Skill changes require a new session — remind the user that SESSION.md and auto memory preserve context across sessions.
