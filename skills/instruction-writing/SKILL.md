---
name: instruction-writing
description: Best practices for writing Claude Code instructions (CLAUDE.md, skills, agents, commands). Use when creating, reviewing, or optimizing any instruction file.
---

# Writing Instructions for Claude Code

## Official references
- Best practices: https://code.claude.com/docs/en/best-practices
- Skills: https://code.claude.com/docs/en/skills
- Subagents: https://code.claude.com/docs/en/sub-agents
- Hooks: https://code.claude.com/docs/en/hooks-guide
- Extensions overview: https://code.claude.com/docs/en/features-overview
- Devcontainers: https://code.claude.com/docs/en/devcontainer
- Settings & configuration: https://code.claude.com/docs/en/settings
- Memory: https://code.claude.com/docs/en/memory
- Prompt engineering: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview
- Context engineering: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Building effective agents: https://www.anthropic.com/engineering/building-effective-agents

Always defer to these sources. They are maintained by Anthropic and take precedence.

---

## Formulation principles
- Each instruction must be specific and actionable. No vague terms.
- When prohibiting something (NEVER), always provide the alternative to use instead.
- Reserve emphasis (NEVER, ALWAYS, CRITICAL, YOU MUST, NON-NEGOTIABLE) for dealbreakers only. Overuse dilutes all instructions uniformly.
- Only document what Claude gets wrong. If Claude already does it by default, the instruction is noise — delete it.
- One instruction = one behavior. Do not combine two ideas in one line.
- No contradictions between instructions. If two instructions conflict, resolve or delete one.
- CLAUDE.md + system prompt combined must not exceed ~150 instructions. Fewer is better.
- If a rule must be followed 100% of the time with zero tolerance, use a hook instead of an instruction.

---

## Where to put what

### CLAUDE.md files
- Loaded automatically by walking up the directory tree, then into child directories on demand.
- Load order: managed policy → ancestor directories (root to project) → project root → `.claude/CLAUDE.md` → `.claude/rules/*.md` → child dirs when navigated.
- Global `~/.claude/CLAUDE.md`: personal, tech-agnostic preferences. Loaded every session. Keep minimal.
- Workspace-level CLAUDE.md: company conventions for all projects under that directory.
- Project-level CLAUDE.md: project-specific directives, versioned in the project repo.
- `CLAUDE.local.md`: same as CLAUDE.md but gitignored by convention — for personal project overrides.
- `@path` syntax imports another file's content inline (e.g., `@docs/architecture.md`).
- `!command` executes a shell command and injects its stdout as context (e.g., `!cat pyproject.toml | grep version`).

### `.claude/rules/` directory
- For path-scoped rules that apply only to specific file patterns.
- Each file uses `paths` frontmatter to specify which files trigger it:
  ```yaml
  ---
  paths:
    - "src/**/*.ts"
    - "tests/**/*.ts"
  ---
  Always use explicit return types in TypeScript functions.
  ```

### Skills
- Specialized knowledge loaded on demand based on `description` keyword matching.
- Language, framework, architecture, connectors — anything domain-specific.
- If an instruction is language/framework specific, it belongs in a skill, not CLAUDE.md.
- If an instruction is domain/business specific, it belongs in a project-level skill.

### Agents (subagents)
- Specialized executors with isolated context and specific tools.
- Use for tasks that benefit from focused context, parallel execution, or restricted tool access.

### Commands
- Repeatable workflows triggered explicitly by the user.

### Hooks
- Programmatic enforcement of rules that must be followed 100% of the time.
- Use hooks when an instruction is consistently violated despite rewording.
- Escalation path: reword instruction → add "Violation = stop" pattern → hook.

### Placement rule
- Global and project CLAUDE.md files merge (all layers loaded).
- Skills, agents, commands: project-level overrides global on name collision.

---

## Skills reference

### Frontmatter fields
```yaml
---
name: my-skill                    # Optional. Defaults to filename.
description: "When to activate"   # Recommended. Controls auto-activation via keyword matching.
disable-model-invocation: true    # Prevents auto-activation. Skill only loads via /command or explicit reference.
user-invocable: /my-command       # Makes skill callable as /my-command by the user.
allowed-tools:                    # Restrict which tools can be used when skill is active.
  - Read
  - Bash(git log:*)
model: claude-sonnet-4-5-20250514  # Override model for this skill.
context: fork                     # Run in a forked context (subagent). Useful for expensive operations.
agent: my-agent                   # Route this skill's execution to a specific agent.
argument-hint: "describe the bug" # Hint shown to user for /command argument.
hooks:                            # Hooks that activate when this skill is loaded.
  PreToolUse:
    - command: "validate.sh"
---
```

### Skill types
- **Single file**: `skills/my-skill.md` — simple, self-contained.
- **Directory**: `skills/my-skill/SKILL.md` — allows companion files (templates, examples) alongside the skill.

### Dynamic context in skills
- `${CLAUDE_SKILL_DIR}` — resolves to the skill's directory path. Use for referencing companion files.
- `$ARGUMENTS` / `$ARGUMENTS[0]`, `$ARGUMENTS[1]` — user-provided arguments when invoked as /command.
- `!command` — shell command whose stdout is injected as context at load time.

---

## Subagents reference

### Frontmatter fields
```yaml
---
name: my-agent                    # Required.
description: "What this agent does" # Required. Also used for @agent routing.
tools:                            # Allowlist of tools.
  - Read
  - Write
  - Bash(npm test:*)
disallowedTools:                  # Denylist (alternative to allowlist).
  - WebFetch
model: claude-sonnet-4-5-20250514  # Override model.
permissionMode: plan              # bypassPermissions | plan | default
maxTurns: 50                      # Limit agent iterations.
skills:                           # Preload specific skills.
  - python
  - data-modeling
mcpServers:                       # MCP servers available to this agent.
  - postgres-main
memory: project                   # Persistent memory scope: user | project | local
background: true                  # Run in background, don't block main conversation.
isolation: worktree               # Run in isolated git worktree.
hooks:                            # Agent-specific hooks.
  PreToolUse:
    - command: "check.sh"
---
```

### Agent design principles
- Give agents focused scope — one domain, not everything.
- Restrict tools to what the agent actually needs.
- Use `skills` field to preload relevant knowledge.
- Use `memory` field for agents that accumulate expertise over time.
- Use `isolation: worktree` for agents that modify files in parallel.

---

## Hooks reference

### Event types
| Event | When it fires |
|---|---|
| SessionStart | Session begins |
| UserPromptSubmit | User sends a message (can modify/block) |
| PreToolUse | Before a tool executes (can block) |
| PostToolUse | After a tool completes |
| PostToolUseFailure | After a tool fails |
| PermissionRequest | When permission is needed |
| Notification | When a notification is sent |
| SubagentStart / SubagentStop | Subagent lifecycle |
| Stop | Claude stops generating |
| TeammateIdle | Teammate becomes idle |
| TaskCompleted | Background task completes |
| InstructionsLoaded | CLAUDE.md files loaded |
| ConfigChange | Configuration changes |
| WorktreeCreate / WorktreeRemove | Worktree lifecycle |
| PreCompact | Before context compaction |
| SessionEnd | Session ends |

### Hook types
- **command**: runs a shell command. Receives JSON on stdin, returns JSON on stdout.
- **http**: sends HTTP request to a URL.
- **prompt**: injects a prompt into the conversation.
- **agent**: delegates to a subagent.

### When to use hooks vs instructions
- Hooks: zero-tolerance rules, automated checks, programmatic enforcement.
- Instructions: guidelines, preferences, conventions that allow judgment.

---

## Context engineering principles

### Context window is the #1 resource
- Everything Claude knows comes from context. Manage it deliberately.
- Keep CLAUDE.md lean — every instruction competes for attention with the actual task.
- Use skills (on-demand) instead of CLAUDE.md (always-loaded) for specialized knowledge.
- Use subagents to isolate large explorations from the main context.

### Effective context patterns
- **Golden path**: provide the exact workflow, not just constraints. "Do X, then Y, then Z" beats "don't do A, B, or C."
- **Verification criteria**: tell Claude how to check its own work. "After creating the migration, run `make db-check` and verify zero errors."
- **Examples over abstractions**: a concrete example teaches more than a paragraph of rules.
- **Explore → plan → implement → commit**: the recommended workflow for complex tasks.

### Anti-patterns
- Restating Claude's defaults (wastes context, adds noise).
- Contradictory instructions (Claude picks one arbitrarily).
- Excessive emphasis on everything (nothing stands out).
- Loading all knowledge always instead of on-demand via skills.

---

## Audit checklist
Apply to every instruction when reviewing:
1. Is it specific and actionable?
2. Does a NEVER include its alternative?
3. Does Claude already do this by default? If yes, delete.
4. Is it redundant with another instruction? If yes, merge or delete.
5. Is emphasis justified for this specific rule?
6. Is it in the right place (CLAUDE.md vs skill vs agent vs hook vs `.claude/rules/`)?
7. Does it contradict another instruction?
8. Does it include verification criteria where applicable?
