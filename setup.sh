#!/usr/bin/env bash
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
WORKSPACE=""

usage() {
    echo "Usage: $0 [--workspace <path>]"
    echo ""
    echo "Deploy claude-forge symlinks."
    echo ""
    echo "Options:"
    echo "  --workspace <path>  Workspace root for company layer (e.g., ~/dev)"
    echo ""
    echo "Creates:"
    echo "  ~/.claude/CLAUDE.md    → forge CLAUDE.md (personal preferences)"
    echo "  ~/.claude/skills/      → forge skills/"
    echo ""
    echo "With --workspace <path>:"
    echo "  <path>/atonra/CLAUDE.md    → forge atonra/CLAUDE.md (company conventions)"
    echo "  <path>/atonra/context/     → forge atonra/context/ (infrastructure context)"
    echo "  <path>/atonra/.claude/commands/ → forge atonra/commands/ (shared commands)"
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

echo "Deploying claude-forge from $FORGE_DIR"
echo ""

echo "Personal layer:"
safe_link "$FORGE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

echo ""
echo "Skills:"
safe_link "$FORGE_DIR/skills" "$CLAUDE_DIR/skills"

if [ -n "$WORKSPACE" ]; then
    echo ""
    echo "Company layer (Atonra):"
    safe_link "$FORGE_DIR/atonra/CLAUDE.md" "$WORKSPACE/atonra/CLAUDE.md"
    safe_link "$FORGE_DIR/atonra/context" "$WORKSPACE/atonra/context"
    safe_link "$FORGE_DIR/atonra/commands" "$WORKSPACE/atonra/.claude/commands"
fi

echo ""
echo "Done."
