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
        --help|-h)
            echo "Usage: ./install.sh [--company NAME --workspace DIR]"
            echo ""
            echo "Options:"
            echo "  --company NAME      Company profile to deploy (directory under companies/)"
            echo "  --workspace DIR     Root directory where the company CLAUDE.md will be symlinked"
            echo ""
            echo "Examples:"
            echo "  ./install.sh                                        # personal preferences only"
            echo "  ./install.sh --company atonra --workspace ~/dev     # + Atonra conventions"
            echo ""
            echo "Available company profiles:"
            if [ -d "$FORGE_DIR/companies" ]; then
                for dir in "$FORGE_DIR/companies"/*/; do
                    [ -d "$dir" ] && echo "  - $(basename "$dir")"
                done
            else
                echo "  (none)"
            fi
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run ./install.sh --help for usage."
            exit 1
            ;;
    esac
done

# --- Validate arguments ---
if [[ -n "$COMPANY" && -z "$WORKSPACE" ]]; then
    echo "ERROR: --company requires --workspace"
    exit 1
fi

if [[ -z "$COMPANY" && -n "$WORKSPACE" ]]; then
    echo "ERROR: --workspace requires --company"
    exit 1
fi

if [[ -n "$COMPANY" ]]; then
    COMPANY_DIR="$FORGE_DIR/companies/$COMPANY"
    if [ ! -d "$COMPANY_DIR" ]; then
        echo "ERROR: Company profile not found: $COMPANY_DIR"
        echo "Available profiles:"
        for dir in "$FORGE_DIR/companies"/*/; do
            [ -d "$dir" ] && echo "  - $(basename "$dir")"
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

    # Company skills (if any) → individual symlinks into forge skills/
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
