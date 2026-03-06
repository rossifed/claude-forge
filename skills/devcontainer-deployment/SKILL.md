# Devcontainer Deployment Skill

## When to activate
- User asks about containerizing Claude Code, Docker, devcontainers, portability
- User wants to set up a new machine or make config portable
- User asks about `--init-devcontainer` or the `.devcontainer/` directory

## Official References
- Devcontainer setup: https://code.claude.com/docs/en/devcontainer
- Settings & config hierarchy: https://code.claude.com/docs/en/settings
- Reference implementation: https://github.com/anthropics/claude-code/tree/main/.devcontainer

## Key Concepts

### Config Portability via CLAUDE_CONFIG_DIR
The `CLAUDE_CONFIG_DIR` environment variable overrides where Claude Code looks for `~/.claude/`. This is the foundation of container portability.

### Configuration Hierarchy (from settings doc)
1. Managed settings (highest priority, IT-deployed)
2. CLI arguments
3. Local: `.claude/settings.local.json`
4. Project: `.claude/settings.json`
5. User: `~/.claude/settings.json`

Arrays merge across scopes. More specific scopes override broader ones.

### Memory Files (CLAUDE.md) Load Order
- `~/.claude/CLAUDE.md` (user-level, all projects)
- `CLAUDE.md` or `.claude/CLAUDE.md` (project-level, shared)
- `.claude/CLAUDE.md.local` (local project, not committed)

### Devcontainer Architecture
The official Anthropic devcontainer has three components:
- **Dockerfile**: Node.js 20 base, Claude Code installed globally, ZSH, security tools
- **devcontainer.json**: VS Code integration, volume mounts, env vars, extensions
- **init-firewall.sh**: iptables-based network restriction (default-deny, whitelist only)

### Security Features
- Firewall restricts outbound to: Claude API, GitHub, npm registry, VS Code servers
- Default-deny policy on all other traffic
- Container isolation from host system
- `--dangerously-skip-permissions` is safe inside the firewall (for unattended operation)
- WARNING: does not prevent exfiltration of credentials accessible inside the container

### Deployment Strategies for claude-forge

**Strategy 1 - Bake into image**: COPY forge files into Dockerfile. Best for teams, CI/CD.
**Strategy 2 - Bind-mount**: Mount forge repo from host into container. Best for solo dev, fast iteration.
**Strategy 3 - Auto-clone**: git clone forge in postCreateCommand. Best for zero-setup machines.

### claude-forge Devcontainer (Strategy 2)
The `.devcontainer/` in claude-forge uses bind-mounts:
```
Host: ~/dev/claude-forge/CLAUDE.md   → Container: /home/node/.claude/CLAUDE.md
Host: ~/dev/claude-forge/skills/     → Container: /home/node/.claude/skills/
Host: ~/dev/claude-forge/agents/     → Container: /home/node/.claude/agents/
```

Mounts are read-only. Edits on host are instant inside container.

The `CLAUDE_FORGE_DIR` env var overrides the default path (`~/dev/claude-forge`).

### install.sh --init-devcontainer
Copies `.devcontainer/` into a project directory. With `--company`, adds the company CLAUDE.md as an additional bind-mount.

## Important Notes
- NEVER bake API keys into Docker images. Pass via env var at runtime.
- The firewall requires `--cap-add=NET_ADMIN --cap-add=NET_RAW` in runArgs.
- `postStartCommand` runs the firewall script on each container start.
- `waitFor: postStartCommand` ensures firewall is active before VS Code connects.
