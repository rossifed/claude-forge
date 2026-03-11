#!/usr/bin/env bash
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

usage() {
    echo "Usage: $0 --workspace <path>"
    echo ""
    echo "Deploy claude-forge symlinks."
    echo ""
    echo "  --workspace <path>  Root directory for company workspaces (e.g. ~/dev)"
    echo ""
    echo "Creates:"
    echo "  ~/.claude/CLAUDE.md        → forge CLAUDE.md (personal preferences)"
    echo "  ~/.claude/skills/          → forge skills/ (including atonra/)"
    echo "  <workspace>/atonra/CLAUDE.md → forge atonra/CLAUDE.md (company conventions)"
    exit 1
}

safe_link() {
    local source="$1"
    local target="$2"
    local target_dir
    target_dir="$(dirname "$target")"

    mkdir -p "$target_dir"

    if [ -L "$target" ]; then
        local current
        current="$(readlink "$target")"
        if [ "$current" = "$source" ]; then
            echo "  ✓ $target (already linked)"
            return
        fi
        rm "$target"
        echo "  ↻ $target (updated symlink)"
    elif [ -e "$target" ]; then
        mv "$target" "$target.bak.$(date +%s)"
        echo "  ⚠ $target (backed up existing file)"
    else
        echo "  + $target"
    fi

    ln -s "$source" "$target"
}

WORKSPACE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$WORKSPACE" ]; then
    echo "Error: --workspace is required."
    echo ""
    usage
fi

WORKSPACE="$(cd "$WORKSPACE" && pwd)"

echo "Deploying claude-forge from $FORGE_DIR"
echo ""

echo "Personal layer:"
safe_link "$FORGE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

echo ""
echo "Skills:"
safe_link "$FORGE_DIR/skills" "$CLAUDE_DIR/skills"

echo ""
echo "Atonra company layer:"
safe_link "$FORGE_DIR/atonra/CLAUDE.md" "$WORKSPACE/atonra/CLAUDE.md"

echo ""
echo "Done."
