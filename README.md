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
        agents/                 Symlinked to ~/.claude/agents/
            forge-master.md
        skills/                 Symlinked to ~/.claude/skills/
            instruction-writing/
                SKILL.md
        companies/              Company profiles (opt-in via --company flag)
            atonra/
                CLAUDE.md       Company-wide mandates only (Layer 2)
                skills/
                    python.md           Python/FastAPI/SQLAlchemy conventions (auto-activates)
                    typescript-react.md TypeScript/React/TanStack conventions (auto-activates)
                    data-orchestration.md Dagster/dbt pipeline conventions (auto-activates)
                    fintech.md          Financial data handling (domain skill)
                    scaffold/           Project bootstrapping (/scaffold command)
                        SKILL.md
        feedback/               Behavioral flags (captured via /flag, processed via /review-flags)
            processed/          Flags already turned into instruction improvements
        memory/                 Agent memory (versioned, not symlinked)

## Adding a Company Profile

    mkdir -p companies/mycompany/skills
    # Create companies/mycompany/CLAUDE.md with company conventions
    # Add company-specific skills in companies/mycompany/skills/
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
