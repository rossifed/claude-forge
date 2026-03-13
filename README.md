# claude-forge

Personal Claude Code configuration: preferences, skills, and company conventions.
Single source of truth, symlinked into place.

## Installation

```bash
git clone https://github.com/rossifed/claude-forge.git ~/claude-forge
cd ~/claude-forge
./setup.sh --workspace ~/dev
```

This creates:

| Symlink | Target | Purpose |
|---|---|---|
| `~/.claude/CLAUDE.md` | `CLAUDE.md` | Personal preferences (always loaded) |
| `~/.claude/skills/` | `skills/` | Global skills (loaded on demand) |
| `~/dev/atonra/CLAUDE.md` | `atonra/CLAUDE.md` | Company conventions (walk-up loaded) |
| `~/dev/atonra/context/` | `atonra/context/` | Infrastructure context (`@` included) |

Without `--workspace`, only the personal layer and skills are deployed.

## How Layering Works

Claude Code walks up the directory tree loading every `CLAUDE.md` it finds:

```
Layer 1 (Personal):   ~/.claude/CLAUDE.md              ← always loaded
Layer 2 (Company):    ~/dev/atonra/CLAUDE.md            ← company conventions + @context includes
Layer 3 (Project):    ~/dev/atonra/fundy/CLAUDE.md      ← project-specific
```

Only CLAUDE.md benefits from walk-up. Rules and skills do not.

## Structure

```
claude-forge/
├── CLAUDE.md                      ← personal preferences → ~/.claude/CLAUDE.md
├── setup.sh                       ← deployment script (symlinks)
├── skills/
│   └── skills-builder/
│       └── SKILL.md               ← skill for writing skills and instructions
├── atonra/
│   ├── CLAUDE.md                  ← company conventions → <workspace>/atonra/CLAUDE.md
│   └── context/
│       ├── database-topology.md   ← cluster topology, MCP mapping, constraints
│       ├── dagster-patterns.md    ← pipeline architecture, schema flow
│       ├── python-conventions.md  ← Python stack conventions
│       └── react-conventions.md   ← React/TypeScript stack conventions
└── README.md
```

## Philosophy

- **CLAUDE.md for directives, skills for knowledge.** CLAUDE.md tells Claude *how to behave*. Skills teach Claude *domain expertise*. `@` includes provide factual context.
- **Skills are generic best practices.** Company/project specifics go in CLAUDE.md files, not skills.
- **YAGNI.** Skills are created when needed, not anticipated. Use `/skills-builder` to create them.
- **Self-improving.** Claude is instructed to flag recurring behavioral gaps and propose new instructions or skills.

## Creating Skills

Use the built-in skills-builder:

```
/skills-builder I need a skill for Python async patterns
```

Or ask Claude to create one — the skills-builder auto-activates when the task involves writing Claude Code configuration.
