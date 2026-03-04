# claude-forge

Global Claude Code configuration: preferences, skills, agents, and their supporting files.
Single source of truth for how Claude works across all projects.

## Installation

    git clone https://github.com/rossifed/claude-forge.git ~/claude-forge
    cd ~/claude-forge
    chmod +x install.sh
    ./install.sh

Creates symlinks from this repo to ~/.claude/. Changes are immediately active.

## Structure

    claude-forge/
        CLAUDE.md           Global preferences (symlinked to ~/.claude/)
        DECISIONS.md        Rationale behind each choice
        README.md           This file
        install.sh          Symlink installer
        agents/             Symlinked to ~/.claude/agents/
            forge-master.md     Builds and audits instruction files
        memory/             Agent memory (versioned, not symlinked)
            forge-master-memory.md  Forge-master persistent knowledge
        skills/             Symlinked to ~/.claude/skills/
            instruction-writing/
                SKILL.md        Best practices for writing Claude instructions

## Usage

Work normally with Claude Code. Your CLAUDE.md is loaded every session.

To create or audit instruction files, call the forge-master agent:
    @forge-master review my CLAUDE.md
    @forge-master I need a skill for Python async patterns

## Maintenance

Update when Claude repeatedly does something wrong that current instructions do not prevent.
See DECISIONS.md for rationale behind each choice.