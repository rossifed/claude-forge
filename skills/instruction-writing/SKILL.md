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
- Prompt engineering: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview

Always defer to these sources. They are maintained by Anthropic and take precedence.

## Formulation principles
- Each instruction must be specific and actionable. No vague terms.
- When prohibiting something (NEVER), always provide the alternative to use instead.
- Reserve emphasis (NEVER, ALWAYS, CRITICAL, YOU MUST, NON-NEGOTIABLE) for dealbreakers only. Overuse dilutes all instructions uniformly.
- Only document what Claude gets wrong. If Claude already does it by default, the instruction is noise — delete it.
- One instruction = one behavior. Do not combine two ideas in one line.
- No contradictions between instructions. If two instructions conflict, resolve or delete one.
- CLAUDE.md + system prompt combined must not exceed ~150 instructions. Fewer is better.
- If a rule must be followed 100% of the time with zero tolerance, use a hook instead of an instruction.

## Where to put what
- CLAUDE.md: universal preferences, tech-agnostic. Loaded every session. Keep minimal.
- Skills: specialized knowledge, loaded on demand. Language, framework, architecture, connectors.
- Agents: specialized executors with isolated context and specific tools.
- Commands: repeatable workflows triggered explicitly by the user.
- If an instruction is language/framework specific, it belongs in a skill.
- If an instruction is domain/business specific, it belongs in a project-level skill.
- Global and project CLAUDE.md merge. All other components: project overrides global on name collision.

## Audit checklist
Apply to every instruction when reviewing:
1. Is it specific and actionable?
2. Does a NEVER include its alternative?
3. Does Claude already do this by default? If yes, delete.
4. Is it redundant with another instruction? If yes, merge or delete.
5. Is emphasis justified for this specific rule?
6. Is it in the right place (CLAUDE.md vs skill vs agent vs hook)?
7. Does it contradict another instruction?