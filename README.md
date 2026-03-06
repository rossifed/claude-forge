# claude-forge

Global Claude Code configuration: preferences, skills, agents, and their supporting files.
Single source of truth for how Claude works across all projects.

## Installation

    git clone https://github.com/rossifed/claude-forge.git ~/claude-forge
    cd ~/claude-forge
    chmod +x install.sh

Base install (personal preferences only):

    ./install.sh

With a company profile (e.g., Atonra conventions deployed to your workspace):

    ./install.sh --company atonra --workspace ~/dev

See available profiles:

    ./install.sh --help

## How Layering Works

Claude Code walks up the directory tree loading every `CLAUDE.md` it finds.
This gives you automatic layering with zero copying:

    Layer 1 (Personal):   ~/.claude/CLAUDE.md          ← always loaded
    Layer 2 (Company):    ~/dev/CLAUDE.md               ← loaded for all projects under ~/dev/
    Layer 3 (Project):    ~/dev/my-project/CLAUDE.md    ← project-specific, versioned in project repo

Each layer is a symlink to this repo (Layers 1-2) or a standalone file (Layer 3).
The company file is never copied or edited per project — Open/Closed principle.

## Structure

    claude-forge/
        CLAUDE.md               Global preferences (Layer 1, symlinked to ~/.claude/)
        DECISIONS.md            Rationale behind each choice
        install.sh              Deployment script with company profile support
        agents/                 Symlinked to ~/.claude/agents/ (generic agents)
            forge-master.md
        skills/                 Symlinked to ~/.claude/skills/ (generic skills)
            instruction-writing/
                SKILL.md
            postgresql.md       PostgreSQL patterns (generic)
        atonra/                 Company profile (opt-in via --company flag)
            CLAUDE.md           Company-wide mandates only (Layer 2)
            agents/             Symlinked individually into agents/ at install time
                data-engineer.md
            skills/             Symlinked individually into skills/ at install time
                python.md           Python/FastAPI/SQLAlchemy conventions
                typescript-react.md TypeScript/React/TanStack conventions
                data-orchestration.md Dagster/dbt pipeline conventions
                fintech.md          Financial data handling
                timescaledb.md      TimescaleDB patterns (Atonra stack)
                data-modeling.md    Atonra DB modeling conventions
                scaffold/           Project bootstrapping (/scaffold command)
                    SKILL.md
        feedback/               Behavioral flags (captured via /flag, processed via /review-flags)
            processed/          Flags already turned into instruction improvements
        memory/                 Agent memory (versioned, not symlinked)

## Devcontainer Deployment (Portable)

For portable, reproducible environments across machines, use the devcontainer approach
instead of symlinks. Based on the [official Anthropic devcontainer reference](https://code.claude.com/docs/en/devcontainer).

### Prerequisites

- Docker installed on the machine
- VS Code with [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- `claude-forge` cloned to `~/dev/claude-forge` (or set `CLAUDE_FORGE_DIR` env var)
- `ANTHROPIC_API_KEY` set in your shell profile

### Initialize a project

    ./install.sh --init-devcontainer ~/dev/my-project
    ./install.sh --init-devcontainer ~/dev/my-project --company atonra

This copies `.devcontainer/` into your project with:
- **Dockerfile**: Node.js 20 + Claude Code + ZSH + security tools
- **devcontainer.json**: bind-mounts forge config (CLAUDE.md, skills, agents) from your host
- **init-firewall.sh**: restricts outbound network to Claude API, GitHub, npm only

### How it works

    Host machine                          Container
    ─────────────────────────────────     ─────────────────────────────────
    ~/dev/claude-forge/CLAUDE.md    ───►  /home/node/.claude/CLAUDE.md
    ~/dev/claude-forge/skills/      ───►  /home/node/.claude/skills/
    ~/dev/claude-forge/agents/      ───►  /home/node/.claude/agents/
    ~/dev/my-project/               ───►  /workspace/

Forge files are bind-mounted read-only. Edit them on the host, changes are instant inside the container.

### Usage

    cd ~/dev/my-project
    # VS Code: "Reopen in Container"
    # Or CLI: devcontainer up --workspace-folder .

### On a new machine

    git clone https://github.com/rossifed/claude-forge.git ~/dev/claude-forge
    export ANTHROPIC_API_KEY=sk-...
    # Open any project with .devcontainer/ → everything just works

## Adding a Company Profile

    mkdir -p mycompany/skills mycompany/agents
    # Create mycompany/CLAUDE.md with company conventions
    # Add company-specific skills in mycompany/skills/
    # Add company-specific agents in mycompany/agents/
    ./install.sh --company mycompany --workspace ~/work

## Usage

Work normally with Claude Code. Your CLAUDE.md is loaded every session.

To create or audit instruction files, call the forge-master agent:
    @forge-master review my CLAUDE.md
    @forge-master I need a skill for Python async patterns

## Feedback Loop

When Claude behaves incorrectly in any project, flag it in-context:

    /flag Claude created 5 files when I asked for structure only

This captures a structured incident report to `feedback/` using the session context
Claude already has. Periodically, process accumulated flags into instruction improvements:

    /review-flags

This groups flags by category, cross-references existing instructions, and proposes
specific changes. See DECISIONS.md for the design rationale.

## Maintenance

Update when Claude repeatedly does something wrong that current instructions do not prevent.
See DECISIONS.md for rationale behind each choice.
