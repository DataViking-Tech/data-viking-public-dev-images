# Godot Game Development Base Image

Custom devcontainer image with pre-installed game development tools for fast container startup. Extends `ghcr.io/dataviking-tech/ai-dev-base:edge` which provides core dev tools (Python, Claude, Beads, Gas Town, dev-infra).

## 🚀 Features

- **Godot 4.6.1** - Game engine with all dependencies
- **Python 3.11 + uv** - Package management
- **Bun** - Fast JavaScript runtime
- **Claude CLI** - AI coding assistant
- **beads** - Issue tracking CLI
- **Gas Town (gt)** - Multi-agent workspace manager
- **Render bridges** - GPU rendering bridge (render_bridge, godot_render_bridge)
- **Agent configs** - Pre-built Claude, Copilot, and Roo agent configurations
- **dev-infra utilities** - Credential caching, project setup, image-versions
- **System packages** - ffmpeg, build tools, multimedia libraries

## 📦 Usage

### In your devcontainer.json

```json
{
  "name": "My Game Project",
  "image": "ghcr.io/dataviking-tech/godot-game-dev-image:edge",

  "customizations": {
    "vscode": {
      "extensions": [
        "geequlim.godot-tools"
      ]
    }
  },

  "postCreateCommand": "bash .devcontainer/postCreateCommand.sh"
}
```

### Minimal postCreateCommand.sh

```bash
#!/bin/bash
set -e

# All tools are pre-installed in the Docker image under /opt/
# This script handles project-specific setup only

# Project-specific setup here

echo "✅ Container ready!"
```

## 🎯 Benefits

**Fast Startup:** 5-15 seconds (vs 3-5 minutes with runtime downloads)

**Consistent Environments:** Same image across all projects

**Disk Space Savings:** ~40% reduction vs per-project installations

## 🔄 Version Management

Check installed tool versions:
```bash
image-versions  # Shows all installed tool versions
```

Update to new version:
1. Edit `devcontainer.json` image tag
2. Rebuild: `Ctrl+Shift+P` → "Rebuild Container"

## 📚 Documentation

- [CHANGELOG](docs/CHANGELOG.md) - Version history
- [UPGRADING](docs/UPGRADING.md) - Migration guides
- [Testing](tests/) - Validation scripts

## 🏗️ Building Locally

```bash
docker build -t godot-game-dev:local .
docker run -it godot-game-dev:local bash
```

---

**Built with ❤️ by DataViking-Tech**