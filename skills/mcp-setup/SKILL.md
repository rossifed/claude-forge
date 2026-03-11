---
name: mcp-setup
description: "Install, configure, or troubleshoot MCP servers for Claude Code — stdio (npm packages), HTTP, and SSE transports"
user-invocable: true
argument-hint: "server name or package"
---

# MCP Setup

Interactive workflow to add an MCP server to Claude Code. Handles stdio (npm), HTTP, and SSE transports.

## Step 0 — Identify transport

Ask the user (or infer from context):

| Signal | Transport |
|---|---|
| npm package name, `npx`, global install | **stdio** |
| URL ending in `/mcp`, REST-style endpoint | **HTTP** |
| URL with `/sse`, event-stream | **SSE** |

If unclear, ask: "Is this an npm package you run locally, or a remote URL?"

---

## Branch A — HTTP / SSE

1. **Gather info.** Ask: server name, URL, auth method (none / header / OAuth).
2. **Choose scope.** Recommend `user` for personal infra, `project` for team-shared servers without credentials.
3. **Register.**
   ```
   claude mcp add --transport http|sse --scope <scope> <name> <url>
   ```
   Add `--header "Authorization: Bearer $TOKEN"` if header auth.
4. **Verify.** Tell the user: "Restart Claude Code, then run `/mcp` to check the server appears and connects."

---

## Branch B — stdio (npm packages)

### B1 — Resolve Node.js paths

Find the **permanent** absolute paths for `node` and `npm`. NEVER use:
- `npx` — re-downloads on every run, breaks in non-interactive shells
- fnm temp paths (`/run/user/.../fnm_multishells/...`) — vanish between sessions
- Relative paths or bare commands (`node`, `npm`) — depend on shell PATH

**How to find permanent paths:**

```bash
# fnm users
ls ~/.local/share/fnm/node-versions/*/installation/bin/node
# nvm users
ls ~/.nvm/versions/node/*/bin/node
# System install
which node  # only if not managed by fnm/nvm
```

Pick the latest LTS version. Store as `$NODE_BIN` (e.g., `/home/user/.local/share/fnm/node-versions/v24.14.0/installation/bin/node`).

Derive `$NPM_BIN` from the same directory: `$(dirname $NODE_BIN)/npm`.

### B2 — Gather package info

Ask the user:
- npm package name (e.g., `@bytebase/dbhub`, `mcp-clickhouse`)
- Connection info the package needs (DSN, config file, env vars) — check the package README if unsure

### B3 — Install globally

```bash
$NPM_BIN install -g <package>
```

Then find the installed entrypoint:

```bash
readlink -f $($NPM_BIN bin -g)/<binary-name>
```

Store as `$ENTRYPOINT` (absolute `.js` path).

### B4 — Config file (if needed)

If the package uses a config file (e.g., dbhub uses TOML):
- **One config file per source** — never bundle multiple sources in one file. Each source fails independently.
- Name the file after the source: `~/.config/<package-name>/<source-name>.toml` (see Naming section)
- Set `chmod 600`
- Populate with the user's connection info
- Store path as `$CONFIG_PATH`

### B5 — Register in claude.json

Build the `mcpServers` entry for `~/.claude.json`:

```json
{
  "mcpServers": {
    "<name>": {
      "command": "$NODE_BIN",
      "args": ["$ENTRYPOINT", ...package-specific-args],
      "scope": "user"
    }
  }
}
```

Package-specific args examples:
- dbhub: `["$ENTRYPOINT", "--config", "$CONFIG_PATH"]`
- mcp-clickhouse: `["$ENTRYPOINT"]` with env vars for connection

Use `claude mcp add` when possible. Fall back to manual `~/.claude.json` edit when `claude mcp add` doesn't support all needed fields (e.g., custom env).

### B6 — Verify

Tell the user: "Restart Claude Code, then run `/mcp` to check the server appears and connects."

If it fails:
1. Check the entrypoint exists: `ls -la $ENTRYPOINT`
2. Test manually: `$NODE_BIN $ENTRYPOINT --help` (or equivalent)
3. Check `~/.claude.json` syntax: valid JSON, correct absolute paths
4. Check config file permissions and content

---

## Naming

When creating an MCP server, **one name must be used everywhere:** MCP server name in `~/.claude.json`, source ID in the config file, and config filename. No translation between layers.

**Example:** a name like `pg-financial-hetzner-test` becomes:
- MCP server key: `"pg-financial-hetzner-test": { ... }` in `~/.claude.json`
- Source ID: `id = "pg-financial-hetzner-test"` in the TOML config
- Config filename: `pg-financial-hetzner-test.toml`

**When the user hasn't defined a naming convention yet**, propose one. Suggest `{db}-{domain}-{infra}-{env}` as a starting point (e.g., `pg-financial-hetzner-test`, `ch-analytics-aws-prod`). Let the user adjust or define their own. Once chosen, record it in the appropriate CLAUDE.md (company or project layer).

---

## Key rules

- **NEVER use `npx` for stdio MCP servers** — install globally with `npm install -g`, use absolute paths to both `node` and the JS entrypoint. npx re-downloads each time and fails in non-interactive shells.
- **NEVER use fnm/nvm temp paths** (`/run/user/.../fnm_multishells/...`) — always resolve to the permanent installation path via `readlink -f`.
- **Credentials stay local** — MCP configs live in `~/.claude.json` and `~/.config/`, never committed to repos.
- **Scope default:** `user` for personal infra, `project` only for team-shared servers without credentials.
- **Challenge before acting** — if the user provides an approach (e.g., "use npx"), evaluate it against these rules and explain why a different approach is better.
