# data-viking-public-dev-images

Public dev container images built and managed in a single monorepo.

## Images

| Image | Description | Registry |
|-------|-------------|----------|
| [ai-dev-base](ai-dev-base/) | Foundation image: Python 3.11, Node.js, Claude CLI, Beads, Gas Town, dev-infra | `ghcr.io/dataviking-tech/ai-dev-base` |
| [godot-game-dev](godot-game-dev/) | Godot 4.5.1 game development environment | `ghcr.io/dataviking-tech/godot-game-dev-image` |
| [dbt-postgres](dbt-postgres/) | dbt-core + dbt-postgres data engineering environment | `ghcr.io/dataviking-tech/dbt-postgres` |

## Architecture

`ai-dev-base` is the foundation image built in this repo. It provides:
- Python 3.11 (via uv), Bun, Node.js
- Claude CLI, GitHub CLI, OpenAI Codex
- Beads issue tracking, Gas Town workspace manager
- Dev-infra utilities, agent configurations

Downstream images (`godot-game-dev`, `dbt-postgres`) `FROM ghcr.io/dataviking-tech/ai-dev-base:edge` and add domain-specific tools.

When `ai-dev-base` is pushed to `main`, the edge build publishes the new base image and then automatically dispatches edge rebuilds for all downstream images (chain rebuild).

## Versioning

Each image is versioned independently using `<image>/vX.Y.Z` tags (e.g. `godot-game-dev/v1.2.3`, `ai-dev-base/v1.0.0`).

Tags are created automatically on PR merge based on semver labels:

| Label | Effect |
|-------|--------|
| `semver:patch` | Bug fixes, docs |
| `semver:minor` | New features (backward-compatible) |
| `semver:major` | Breaking changes |
| `semver:skip` | No release |

## CI Isolation

Workflows are scoped by path filters. A PR touching only `dbt-postgres/` will NOT trigger godot or ai-dev-base workflows.

PRs that touch `ai-dev-base/` will also trigger downstream PR builds (godot, dbt) which build the base image locally to validate the full stack.
