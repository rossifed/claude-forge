#!/bin/bash
# claude-forge install script
# Creates symlinks from this repo to ~/.claude/

set -e

FORGE_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing claude-forge..."
echo "Source: $FORGE_DIR"
echo "Target: $CLAUDE_DIR"

# Safety check: forge must not be inside ~/.claude/
if [[ "$FORGE_DIR" == "$CLAUDE_DIR"* ]]; then
    echo "ERROR: claude-forge must not be inside $CLAUDE_DIR"
    echo "Move it to another location (e.g. ~/dev/claude-forge)"
    exit 1
fi

mkdir -p "$CLAUDE_DIR"

# Remove existing targets (files, symlinks, or directories) to avoid nesting
for target in CLAUDE.md skills agents; do
    if [ -L "$CLAUDE_DIR/$target" ]; then
        rm "$CLAUDE_DIR/$target"
    elif [ -e "$CLAUDE_DIR/$target" ]; then
        echo "WARNING: $CLAUDE_DIR/$target exists and is not a symlink. Backing up to $CLAUDE_DIR/$target.bak"
        mv "$CLAUDE_DIR/$target" "$CLAUDE_DIR/$target.bak"
    fi
done

ln -s "$FORGE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "  Linked CLAUDE.md"

ln -s "$FORGE_DIR/skills" "$CLAUDE_DIR/skills"
echo "  Linked skills/"

ln -s "$FORGE_DIR/agents" "$CLAUDE_DIR/agents"
echo "  Linked agents/"

echo ""
echo "claude-forge installed. Changes in $FORGE_DIR are immediately active."
echo "Restart Claude Code to pick up the new configuration."
echo ""
echo "Note: memory/ and DECISIONS.md are NOT symlinked."
echo "They live in the repo only and are accessed by agents directly."