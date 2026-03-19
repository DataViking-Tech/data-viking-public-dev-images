# Edge Image Rollback Runbook

## Overview

Every edge build automatically preserves the previous `:edge` image as
`:edge-previous` before publishing the new one. This gives a one-step rollback
to the last known-good nightly for all three images.

## Tags

| Tag | Description | Mutability |
|-----|-------------|------------|
| `:edge` | Current nightly build | Replaced daily |
| `:edge-previous` | The nightly build immediately before current `:edge` | Replaced daily |

All three images follow this scheme:
- `ghcr.io/dataviking-tech/ai-dev-base`
- `ghcr.io/dataviking-tech/godot-game-dev-image`
- `ghcr.io/dataviking-tech/dbt-postgres`

## Rollback Procedure

### 1. Switch a devcontainer to edge-previous

Edit the `devcontainer.json` or `Dockerfile` that references the broken image:

```diff
- "image": "ghcr.io/dataviking-tech/ai-dev-base:edge"
+ "image": "ghcr.io/dataviking-tech/ai-dev-base:edge-previous"
```

Then rebuild the container (`Dev Containers: Rebuild Container` in VS Code, or
`docker compose up --build`).

### 2. Retag edge-previous back to edge (registry-level rollback)

If the broken `:edge` is affecting many consumers and you want to restore the
previous image as the current `:edge` without waiting for a new build:

```bash
# Log in to GHCR
echo "$GITHUB_TOKEN" | docker login ghcr.io -u USERNAME --password-stdin

# Rollback ai-dev-base
docker buildx imagetools create \
  --tag ghcr.io/dataviking-tech/ai-dev-base:edge \
  ghcr.io/dataviking-tech/ai-dev-base:edge-previous

# Rollback godot-game-dev-image
docker buildx imagetools create \
  --tag ghcr.io/dataviking-tech/godot-game-dev-image:edge \
  ghcr.io/dataviking-tech/godot-game-dev-image:edge-previous

# Rollback dbt-postgres
docker buildx imagetools create \
  --tag ghcr.io/dataviking-tech/dbt-postgres:edge \
  ghcr.io/dataviking-tech/dbt-postgres:edge-previous
```

> **Note:** This overwrites `:edge` with the `:edge-previous` manifest without
> rebuilding. The next scheduled nightly build will overwrite both tags again.

### 3. Pin to a specific release (long-term fix)

If edge instability is recurring, pin to a stable release tag instead:

```jsonc
// devcontainer.json
"image": "ghcr.io/dataviking-tech/ai-dev-base:v1.2"  // tracks patch updates only
```

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full versioning scheme.

## Chain Rebuild Considerations

`ai-dev-base` is the foundation for `godot-game-dev-image` and `dbt-postgres`.
When `ai-dev-base:edge` is updated, downstream edge builds are automatically
triggered. If you roll back `ai-dev-base:edge`, the downstream images still
reference the old (broken) base until their next rebuild.

To force a full chain rollback:

1. Roll back `ai-dev-base:edge` (see above)
2. Trigger downstream rebuilds manually via GitHub Actions:
   - Go to **Actions** > **Godot: Build and Publish Edge** > **Run workflow**
   - Go to **Actions** > **dbt-postgres: Build and Publish Edge** > **Run workflow**

## Verifying the Rollback

```bash
# Check which commit built the current edge
docker buildx imagetools inspect ghcr.io/dataviking-tech/ai-dev-base:edge

# Compare with edge-previous
docker buildx imagetools inspect ghcr.io/dataviking-tech/ai-dev-base:edge-previous
```

## Limitations

- Only one previous build is preserved. There is no `:edge-previous-2`.
- The very first edge build has no `:edge-previous` (nothing to retag).
- `:edge-previous` is overwritten on every edge build, so act quickly if the
  current `:edge` is broken and `:edge-previous` is still the good version.
