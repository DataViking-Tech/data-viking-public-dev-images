# Credential Cache Component

Generic credential caching framework for devcontainers. Provides persistent authentication across container rebuilds with automatic token conversion in Codespaces.

**Key Features:**
- ✅ Credentials persist across container rebuilds (bind-mounted `temp/auth/`)
- ✅ Auto-converts `GITHUB_TOKEN` to cached OAuth in GitHub Codespaces
- ✅ Non-blocking - authentication failures never prevent container startup

## Quick Start

### 1. Add bind mounts to `.devcontainer/devcontainer.json`

```json
{
  "mounts": [
    "source=${localWorkspaceFolder}/temp/auth,target=/workspaces/${localWorkspaceFolderBasename}/temp/auth,type=bind",
    "source=${localWorkspaceFolder}/temp/auth/gh-config,target=/home/vscode/.config/gh,type=bind"
  ]
}
```

### 2. Call from postStartCommand

In `.devcontainer/postStartCommand.sh`:

```bash
#!/bin/bash
source /opt/dev-infra/credential_cache.sh
setup_credential_cache "github" "cloudflare"
```

### 3. Ensure temp/ is gitignored

Add to `.gitignore`:
```
temp/
```

That's it! Credentials will now persist across rebuilds.

## Supported Services

### GitHub CLI (`github`)

**Required Mount:**
```json
"source=${localWorkspaceFolder}/temp/auth/gh-config,target=/home/vscode/.config/gh,type=bind"
```

**Authentication Flow:**
1. **Cached:** Checks `temp/auth/gh-config/hosts.yml`
2. **Automatic:** Converts `GITHUB_TOKEN` environment variable (Codespaces)
3. **Interactive:** Prompts user to run `gh auth login`

**Cache Location:** `temp/auth/gh-config/hosts.yml`

---

### Cloudflare (`cloudflare`)

**No bind mount required** - Uses symlink to `~/.wrangler/config/`

**Note**: The component creates a symlink from `temp/auth/wrangler/default.toml` to `~/.wrangler/config/default.toml` automatically.

**Authentication Flow:**
1. **Cached:** Checks `temp/auth/cloudflare_api_token` or `temp/auth/wrangler/default.toml`
2. **Automatic:** Caches `CLOUDFLARE_API_TOKEN` if set
3. **Interactive:** User runs `wrangler login`

**Cache Locations:**
- API Token: `temp/auth/cloudflare_api_token` (permissions: 600)
- OAuth Config: `temp/auth/wrangler/default.toml` (symlinked to `~/.wrangler/config/default.toml`)

## Configuration

### Directory Structure

```
project-root/
├── temp/                          # Gitignored
│   └── auth/                      # Credential cache root
│       ├── gh-config/             # GitHub CLI
│       │   └── hosts.yml          # OAuth tokens (600)
│       ├── wrangler/              # Cloudflare Wrangler
│       │   └── default.toml       # OAuth config
│       └── cloudflare_api_token   # Cloudflare API token (600)
```

### Security

- All credential files use 600 permissions (owner-only)
- `temp/` directory must be gitignored
- Each workspace has isolated credentials
- Bind mounts persist credentials across rebuilds

## Troubleshooting

### Credentials not persisting

**Issue:** Auth prompts on every container start

**Solution:** Verify bind mounts in `.devcontainer/devcontainer.json`
```bash
# Check if mounts are active
mount | grep temp/auth
```

### Permission denied errors

**Issue:** Cannot write to credential files

**Solution:** Check directory permissions
```bash
chmod 700 ~/temp/auth/gh-config
chmod 600 ~/temp/auth/gh-config/hosts.yml
```

### Token expired

**GitHub:**
```bash
gh auth refresh
# or
gh auth login
```

**Cloudflare:**
```bash
wrangler login
# Token cached automatically
```

### Reset credentials

```bash
# Remove cached credentials
rm -rf temp/auth/<service>/

# Re-authenticate
gh auth login  # for GitHub
wrangler login # for Cloudflare
```

### Wrangler symlink issues

**Issue:** Cloudflare Wrangler not using cached config

**Check:**
```bash
ls -la ~/.wrangler/config/default.toml
# Should show symlink to temp/auth/wrangler/default.toml
```

**Solution:**
```bash
# Re-create symlink
mkdir -p ~/.wrangler/config
ln -sf "$(git rev-parse --show-toplevel)/temp/auth/wrangler/default.toml" ~/.wrangler/config/default.toml
```
