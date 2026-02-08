# Contributing

## Versioning

This repo uses **automatic semver tagging** via PR labels. When a PR is merged to `main`, the auto-tag workflow reads the label and creates the next version tag, scoped to the image that changed.

| Label | Effect |
|---|---|
| `semver:patch` | Bump patch (e.g. v2.1.3 -> v2.1.4) — bug fixes, docs |
| `semver:minor` | Bump minor (e.g. v2.1.3 -> v2.2.0) — new features, backward-compatible |
| `semver:major` | Bump major (e.g. v2.1.3 -> v3.0.0) — breaking changes |
| `semver:skip` | No release on merge |
| *(no label)* | No release on merge |

Apply **exactly one** `semver:*` label to your PR before merging. Multiple semver labels will cause the workflow to fail.

## Tag Format

Tags are prefixed with the image name: `godot-game-dev/v1.2.3`, `dbt-postgres/v1.0.0`.

## Adding a New Image

1. Create a directory at the repo root: `my-image/`
2. Add `Dockerfile`, `.devcontainer/`, `tests/`, `docs/`
3. Create workflows in `.github/workflows/` following existing patterns
4. Scope all workflow triggers with `paths:` filters to your directory
5. Seed an initial tag: `my-image/v1.0.0`
