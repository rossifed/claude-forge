#!/bin/bash
# claude-forge install script
# Creates symlinks from this repo to ~/.claude/ and optionally deploys a company profile.
#
# Usage:
#   ./install.sh                                          # base only (personal preferences)
#   ./install.sh --company atonra --workspace ~/dev       # base + company layer

set -e

FORGE_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMPANY=""
WORKSPACE=""
INIT_DEVCONTAINER=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --company)
            COMPANY="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --init-devcontainer)
            INIT_DEVCONTAINER="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./install.sh [--company NAME --workspace DIR]"
            echo "       ./install.sh --init-devcontainer PROJECT_DIR [--company NAME]"
            echo ""
            echo "Options:"
            echo "  --company NAME              Company profile to deploy (directory at repo root)"
            echo "  --workspace DIR             Root directory where the company CLAUDE.md will be symlinked"
            echo "  --init-devcontainer DIR     Copy devcontainer config into a project directory"
            echo ""
            echo "Examples:"
            echo "  ./install.sh                                        # personal preferences only (symlinks)"
            echo "  ./install.sh --company atonra --workspace ~/dev     # + Atonra conventions (symlinks)"
            echo "  ./install.sh --init-devcontainer ~/dev/my-project   # setup devcontainer in a project"
            echo "  ./install.sh --init-devcontainer ~/dev/my-project --company atonra"
            echo ""
            echo "Available company profiles:"
            for dir in "$FORGE_DIR"/*/; do
                if [ -f "$dir/CLAUDE.md" ]; then
                    echo "  - $(basename "$dir")"
                fi
            done
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run ./install.sh --help for usage."
            exit 1
            ;;
    esac
done

# --- Devcontainer init mode ---
if [[ -n "$INIT_DEVCONTAINER" ]]; then
    PROJECT_DIR="$(realpath "$INIT_DEVCONTAINER")"
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "ERROR: Project directory does not exist: $PROJECT_DIR"
        exit 1
    fi

    DEVCONTAINER_SRC="$FORGE_DIR/.devcontainer"
    DEVCONTAINER_DST="$PROJECT_DIR/.devcontainer"

    if [ -d "$DEVCONTAINER_DST" ]; then
        echo "WARNING: $DEVCONTAINER_DST already exists. Overwriting."
    fi

    mkdir -p "$DEVCONTAINER_DST"
    cp "$DEVCONTAINER_SRC/Dockerfile" "$DEVCONTAINER_DST/Dockerfile"
    cp "$DEVCONTAINER_SRC/init-firewall.sh" "$DEVCONTAINER_DST/init-firewall.sh"
    cp "$DEVCONTAINER_SRC/devcontainer.json" "$DEVCONTAINER_DST/devcontainer.json"

    # If company specified, add company CLAUDE.md mount to devcontainer.json
    if [[ -n "$COMPANY" ]]; then
        COMPANY_DIR="$FORGE_DIR/$COMPANY"
        if [ ! -d "$COMPANY_DIR" ] || [ ! -f "$COMPANY_DIR/CLAUDE.md" ]; then
            echo "ERROR: Company profile not found: $COMPANY_DIR"
            exit 1
        fi

        # Add company CLAUDE.md as a bind-mount to workspace root
        COMPANY_MOUNT="\"source=\${localEnv:CLAUDE_FORGE_DIR:\${localEnv:HOME}/dev/claude-forge}/$COMPANY/CLAUDE.md,target=/workspace/CLAUDE.md,type=bind,readonly\""

        # Insert the company mount into the mounts array
        sed -i "s|\"source=\${localEnv:CLAUDE_FORGE_DIR:\${localEnv:HOME}/dev/claude-forge}/agents,target=/home/node/.claude/agents,type=bind,readonly\"|\"source=\${localEnv:CLAUDE_FORGE_DIR:\${localEnv:HOME}/dev/claude-forge}/agents,target=/home/node/.claude/agents,type=bind,readonly\",\n    $COMPANY_MOUNT|" "$DEVCONTAINER_DST/devcontainer.json"

        echo "  Company profile '$COMPANY' mount added to devcontainer.json"
    fi

    echo ""
    echo "Devcontainer initialized in: $DEVCONTAINER_DST"
    echo ""
    echo "Prerequisites:"
    echo "  1. Set CLAUDE_FORGE_DIR env var (or clone forge to ~/dev/claude-forge)"
    echo "  2. Set ANTHROPIC_API_KEY in your shell profile"
    echo ""
    echo "Usage:"
    echo "  Open $PROJECT_DIR in VS Code → 'Reopen in Container'"
    echo "  Or: cd $PROJECT_DIR && devcontainer up --workspace-folder ."
    exit 0
fi

# --- Validate arguments (symlink mode) ---
if [[ -n "$COMPANY" && -z "$WORKSPACE" ]]; then
    echo "ERROR: --company requires --workspace"
    exit 1
fi

if [[ -z "$COMPANY" && -n "$WORKSPACE" ]]; then
    echo "ERROR: --workspace requires --company"
    exit 1
fi

if [[ -n "$COMPANY" ]]; then
    COMPANY_DIR="$FORGE_DIR/$COMPANY"
    if [ ! -d "$COMPANY_DIR" ] || [ ! -f "$COMPANY_DIR/CLAUDE.md" ]; then
        echo "ERROR: Company profile not found: $COMPANY_DIR"
        echo "Available profiles:"
        for dir in "$FORGE_DIR"/*/; do
            if [ -f "$dir/CLAUDE.md" ]; then
                echo "  - $(basename "$dir")"
            fi
        done
        exit 1
    fi

    WORKSPACE="$(realpath "$WORKSPACE")"
    if [ ! -d "$WORKSPACE" ]; then
        echo "ERROR: Workspace directory does not exist: $WORKSPACE"
        exit 1
    fi
fi

# Safety check: forge must not be inside ~/.claude/
if [[ "$FORGE_DIR" == "$CLAUDE_DIR"* ]]; then
    echo "ERROR: claude-forge must not be inside $CLAUDE_DIR"
    echo "Move it to another location (e.g. ~/dev/claude-forge)"
    exit 1
fi

mkdir -p "$CLAUDE_DIR"

# --- Helper: safe symlink ---
safe_link() {
    local source="$1"
    local target="$2"
    local label="$3"

    if [ -L "$target" ]; then
        rm "$target"
    elif [ -e "$target" ]; then
        echo "  WARNING: $target exists and is not a symlink. Backing up to $target.bak"
        mv "$target" "$target.bak"
    fi

    ln -s "$source" "$target"
    echo "  Linked $label"
}

# --- Base deployment (always) ---
echo "Installing claude-forge..."
echo "  Source: $FORGE_DIR"
echo "  Target: $CLAUDE_DIR"
echo ""

safe_link "$FORGE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md (personal preferences)"
safe_link "$FORGE_DIR/skills" "$CLAUDE_DIR/skills" "skills/"
safe_link "$FORGE_DIR/agents" "$CLAUDE_DIR/agents" "agents/"

# --- Company deployment (optional) ---
if [[ -n "$COMPANY" ]]; then
    echo ""
    echo "Deploying company profile: $COMPANY"
    echo "  Workspace: $WORKSPACE"
    echo ""

    # Company CLAUDE.md → workspace root
    safe_link "$COMPANY_DIR/CLAUDE.md" "$WORKSPACE/CLAUDE.md" "CLAUDE.md ($COMPANY conventions → $WORKSPACE/)"

    # Company skills → individual symlinks into forge skills/
    if [ -d "$COMPANY_DIR/skills" ]; then
        for skill_entry in "$COMPANY_DIR/skills"/*; do
            skill_name="$(basename "$skill_entry")"
            if [ -f "$skill_entry" ]; then
                safe_link "$skill_entry" "$FORGE_DIR/skills/$skill_name" "skills/$skill_name ($COMPANY)"
            elif [ -d "$skill_entry" ] && [ -f "$skill_entry/SKILL.md" ]; then
                safe_link "$skill_entry" "$FORGE_DIR/skills/$skill_name" "skills/$skill_name/ ($COMPANY)"
            fi
        done
    fi

    # Company agents → individual symlinks into forge agents/
    if [ -d "$COMPANY_DIR/agents" ]; then
        for agent_entry in "$COMPANY_DIR/agents"/*; do
            agent_name="$(basename "$agent_entry")"
            if [ -f "$agent_entry" ]; then
                safe_link "$agent_entry" "$FORGE_DIR/agents/$agent_name" "agents/$agent_name ($COMPANY)"
            fi
        done
    fi
fi

# --- Summary ---
echo ""
echo "claude-forge installed successfully."
echo ""
echo "Layers active:"
echo "  Layer 1 (Personal):  $CLAUDE_DIR/CLAUDE.md"
if [[ -n "$COMPANY" ]]; then
    echo "  Layer 2 (Company):   $WORKSPACE/CLAUDE.md  [$COMPANY]"
    echo "  Layer 3 (Project):   <each project>/CLAUDE.md  (you manage these)"
else
    echo "  Layer 2 (Project):   <each project>/CLAUDE.md  (you manage these)"
fi
echo ""
echo "Changes in $FORGE_DIR are immediately active via symlinks."
echo "Restart Claude Code to pick up the new configuration."
