# data-viking-public-dev-images

Public dev container images extending [ai-dev-base](https://github.com/DataViking-Tech/ai-dev-base-image).

## Images

| Image | Description | Registry |
|-------|-------------|----------|
| [godot-game-dev](godot-game-dev/) | Godot 4.5.1 game development environment | `ghcr.io/dataviking-tech/godot-game-dev` |
| [dbt-postgres](dbt-postgres/) | dbt-core + dbt-postgres data engineering environment | `ghcr.io/dataviking-tech/dbt-postgres` |

## Architecture

All images extend `ghcr.io/dataviking-tech/ai-dev-base:edge` which provides:
- Python 3.11 (via uv), Bun, Node.js
- Claude CLI, GitHub CLI, OpenAI Codex
- Beads issue tracking, Gas Town workspace manager
- Dev-infra utilities, agent configurations

Each image adds domain-specific tools on top of the shared base.

## Versioning

Each image is versioned independently using `<image>/vX.Y.Z` tags (e.g. `godot-game-dev/v1.2.3`).

Tags are created automatically on PR merge based on semver labels:

| Label | Effect |
|-------|--------|
| `semver:patch` | Bug fixes, docs |
| `semver:minor` | New features (backward-compatible) |
| `semver:major` | Breaking changes |
| `semver:skip` | No release |

## CI Isolation

Workflows are scoped by path filters. A PR touching only `dbt-postgres/` will NOT trigger godot workflows, and vice versa.
