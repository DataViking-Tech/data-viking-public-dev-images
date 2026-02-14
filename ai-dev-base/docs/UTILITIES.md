# AI Dev Base Image — Installed Utilities

> Auto-generated reference for tools baked into `ai-dev-base`.
> Downstream images append their own sections to this file.

---

## System Packages

| Package           | Description                              |
|-------------------|------------------------------------------|
| `git`             | Distributed version control              |
| `curl`            | URL data transfer                        |
| `wget`            | Network file retrieval                   |
| `build-essential` | GCC, make, and core build toolchain      |
| `nodejs`          | JavaScript runtime (system package)      |
| `tmux`            | Terminal multiplexer (agent sessions)    |
| `sqlite3`         | SQLite CLI (convoy database queries)     |

## Python & Package Managers

| Tool       | Description                                          |
|------------|------------------------------------------------------|
| `uv`       | Fast Python package manager (system-wide)            |
| `uvx`      | Run Python tools in ephemeral environments           |
| `python3`  | Python 3.11 installed via uv, symlinked to `/usr/local/bin` |
| `bun`      | JavaScript/TypeScript runtime and package manager    |

## AI / Dev Tools

| Tool       | Description                                          |
|------------|------------------------------------------------------|
| `claude`   | Claude CLI — Anthropic's AI assistant                |
| `codex`    | OpenAI Codex CLI (installed globally via Bun)        |
| `gh`       | GitHub CLI — repo, PR, and issue management          |
| `bd`       | Beads — issue tracking for AI workflows              |
| `gt`       | Gastown — multi-agent orchestration CLI               |

## Embedded Components

### ai-coding-utils (`/opt/ai-coding-utils`)

Bundled Python packages for workflow integration:

- **slack** — Slack notification helpers
- **beads** — Beads workflow utilities

Dependencies: `requests`, `pyyaml` (installed via uv).
Added to `PYTHONPATH` automatically.

### dev-infra (`/opt/dev-infra`)

Shell components sourced automatically in all interactive shells via `/etc/profile.d/ai-dev-utils.sh` (source: `lib/dev-infra/profile.sh`):

| Script                | Purpose                          |
|-----------------------|----------------------------------|
| `credential_cache.sh` | Credential caching framework    |
| `directories.sh`      | Workspace directory creation    |
| `python_venv.sh`      | Python virtualenv management    |
| `git_hooks.sh`        | Git hooks configuration         |

Also includes a `secrets/` module for secrets management.

### Gastown (`~/gt`)

Multi-agent orchestration for Claude Code sessions. Gastown manages agent coordination, inter-agent messaging, and cost tracking.

**Automatic setup:** On first shell login, `setup_gastown` initializes a workspace at `~/gt/` (persisted via Docker volume) and merges hooks into `~/.claude/settings.json`.

**Claude Code hooks configured automatically:**

| Hook Event         | What it does                                      |
|--------------------|---------------------------------------------------|
| `SessionStart`     | Primes the agent context with workspace state     |
| `PreCompact`       | Re-primes context before compaction               |
| `UserPromptSubmit` | Checks for inter-agent mail and injects messages  |
| `PreToolUse`       | Guards PR workflows (branch creation, PR creation)|
| `Stop`             | Records session cost data                         |

**Common commands:**

```bash
gt status          # Show workspace and agent status
gt doctor          # Health check for gastown installation
gt mail check      # Check for messages from other agents
gt mail send       # Send a message to another agent
gt costs show      # View recorded session costs
gt prime           # Prime agent context with workspace state
gt tap guard       # Run a tap guard (e.g., pr-workflow)
```

**Environment:**

| Variable        | Default     | Description                  |
|-----------------|-------------|------------------------------|
| `GASTOWN_HOME`  | `$HOME/gt`  | Gastown workspace directory  |

### Crew Configuration (`/opt/dev-infra/setup/ensure_crew.sh`)

Downstream projects can declare crew members in `.devcontainer/crew.json`. On container creation, the script reads the config and runs `gt crew add` for each member (idempotent).

**Config format:**

```json
{
  "crew": [
    {"name": "frontend", "description": "UI/UX work"},
    {"name": "backend", "description": "API and pipeline"},
    {"name": "infra", "description": "Deployment and infrastructure"}
  ]
}
```

Simple list format is also supported:

```json
{
  "crew": ["frontend", "backend", "infra"]
}
```

**Requirements:** Gastown must be enabled (`GASTOWN_ENABLED` not set to `false`) and the project must be registered as a rig.

## Shell Aliases

Defined in `lib/dev-infra/profile.sh` (installed to `/etc/profile.d/ai-dev-utils.sh`) and available in every shell:

| Alias      | Expands to   |
|------------|-------------|
| `bd-ready` | `bd ready`  |
| `bd-sync`  | `bd sync`   |
| `bd-list`  | `bd list`   |
| `py`       | `python3`   |
| `pip`      | `pip3`      |
| `gt-status`| `gt status` |
| `gt-doctor`| `gt doctor` |

Projects can add custom aliases by placing a file at
`/workspace/.devcontainer/aliases.sh` — it is sourced automatically.
