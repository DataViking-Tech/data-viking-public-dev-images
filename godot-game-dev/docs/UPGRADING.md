# Upgrading Guide

This guide helps you upgrade between different versions of the Godot Game Development Base Image.

## General Upgrade Process

1. **Check changelog:**
   ```bash
   # Review what changed
   cat docs/CHANGELOG.md
   ```

2. **Update devcontainer.json:**
   ```json
   {
   - "image": "ghcr.io/dataviking-tech/godot-game-dev-image:v1.0.0",
   + "image": "ghcr.io/dataviking-tech/godot-game-dev-image:v1.1.0",
     "remoteEnv": {
   -   "EXPECTED_IMAGE_VERSION": "v1.0.0"
   +   "EXPECTED_IMAGE_VERSION": "v1.1.0"
     }
   }
   ```

3. **Rebuild container:**
   - VS Code: `Ctrl+Shift+P` → "Dev Containers: Rebuild Container"
   - CLI: `devcontainer up --workspace-folder . --rebuild`

4. **Test your project:**
   - Run your test suite
   - Verify tools work: `godot --version`, `python3 --version`, etc.
   - Test asset generation pipeline (if applicable)

## Version-Specific Upgrade Notes

### v1.0.0 (Initial Release)

**From:** Bootstrap scripts (no image)
**To:** v1.0.0 custom image

**Steps:**
1. Create/update `.devcontainer/devcontainer.json`:
   ```json
   {
     "name": "My Project",
     "image": "ghcr.io/dataviking-tech/godot-game-dev-image:v1.0.0",
     "remoteEnv": {
       "EXPECTED_IMAGE_VERSION": "v1.0.0"
     }
   }
   ```

2. Simplify `postCreateCommand.sh`:
   - Remove tool downloads (Godot, Python, Bun, etc.)
   - Keep only: submodule init + project-specific setup
   - Reduce from ~277 lines to ~20 lines

3. First rebuild will download image (~2-3 min one-time)

4. Validate:
   ```bash
   cat /opt/image-version  # Should show v1.0.0
   godot --version         # Should show 4.5.1
   python3 --version       # Should show 3.11.x
   bun --version           # Should show 1.1.38
   ```

**Expected Performance:**
- Startup time: 5-15 seconds (vs 3-5 min before)
- Disk space: ~2.5GB for image (shared across projects)

---

## Rollback Procedure

If you encounter issues with a new version:

1. **Revert devcontainer.json:**
   ```json
   {
     "image": "ghcr.io/dataviking-tech/godot-game-dev-image:v1.0.0",
     "remoteEnv": {
       "EXPECTED_IMAGE_VERSION": "v1.0.0"
     }
   }
   ```

2. **Rebuild container**

3. **Report issue:** https://github.com/DataViking-Tech/data-viking-public-dev-images/issues

---

## Troubleshooting Upgrades

### "Image not found" after upgrade

**Problem:** New image version doesn't exist yet

**Solution:**
```bash
# Check available versions
docker search ghcr.io/dataviking-tech/godot-game-dev-image

# Or check GitHub releases
# https://github.com/DataViking-Tech/data-viking-public-dev-images/releases

# Rollback to previous version
```

### "Tools not updated after rebuild"

**Problem:** Docker cached old image

**Solution:**
```bash
# Force remove cached image
docker image rm ghcr.io/dataviking-tech/godot-game-dev-image:v1.1.0

# Rebuild container (forces fresh pull)
```

### "Container startup is slow after upgrade"

**Problem:** New image might be larger or have additional setup

**Solution:**
1. Check image size: `docker images | grep godot-game-dev-image`
2. Review CHANGELOG for performance notes
3. Report if significantly slower than expected

### "Tests fail after upgrade"

**Problem:** Breaking changes in tools

**Solution:**
1. Check CHANGELOG "Breaking Changes" section
2. Review tool version changes (Godot, Python, etc.)
3. Update project code if necessary
4. Consider rollback if migration is complex

---

## Best Practices

### For Individual Projects

- **Pin to specific versions** (not `latest`)
- **Test upgrades in development branch first**
- **Review changelog before upgrading**
- **Keep notes on project-specific adjustments**

### For Multi-Project Organizations

- **Upgrade one project at a time** (canary deployment)
- **Document project-specific issues**
- **Coordinate upgrade windows** (avoid surprise breakages)
- **Maintain compatibility matrix** (which projects use which versions)

---

## Future Version Placeholders

### Upgrading to v1.1.0

(To be written when v1.1.0 is released)

### Upgrading to v2.0.0

(To be written when v2.0.0 is released - expect breaking changes)
