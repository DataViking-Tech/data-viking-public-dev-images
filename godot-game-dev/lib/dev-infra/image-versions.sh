#!/bin/bash
# Show devcontainer image versions across all projects
#
# Scans WORKSPACES_DIR (default: /workspaces) for projects with
# devcontainer.json and reports their configured image versions.
#
# Install location: /opt/dev-infra/bin/image-versions
# Usage: image-versions
#
# Environment:
#   WORKSPACES_DIR  Directory to scan (default: /workspaces)
#
# Exit codes:
#   0 - Success (status information displayed)

set -e

echo "📦 Devcontainer Image Versions Across Projects"
echo ""
printf "%-30s | %-40s | %s\n" "Project" "Image Version" "Last Updated"
echo "$(printf '%.0s-' {1..100})"

# Default to /workspaces if running in typical devcontainer setup
WORKSPACES_DIR="${WORKSPACES_DIR:-/workspaces}"

# Check if workspaces directory exists
if [ ! -d "$WORKSPACES_DIR" ]; then
    echo "⚠️  Warning: $WORKSPACES_DIR directory not found" >&2
    echo "   Set WORKSPACES_DIR environment variable to scan different location" >&2
    exit 0
fi

# Scan all project directories
FOUND_PROJECTS=false
for project_path in "$WORKSPACES_DIR"/*/; do
    PROJECT_NAME=$(basename "$project_path")
    DEVCONTAINER="$project_path/.devcontainer/devcontainer.json"

    if [ -f "$DEVCONTAINER" ]; then
        FOUND_PROJECTS=true

        # Extract image tag from devcontainer.json
        IMAGE_LINE=$(grep -o '"image"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVCONTAINER" 2>/dev/null || echo "")

        if [ -n "$IMAGE_LINE" ]; then
            IMAGE_TAG=$(echo "$IMAGE_LINE" | sed 's/.*"image"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        else
            IMAGE_TAG="(not found)"
        fi

        # Get last modified date
        UPDATED=$(stat -c %y "$DEVCONTAINER" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

        printf "%-30s | %-40s | %s\n" "$PROJECT_NAME" "$IMAGE_TAG" "$UPDATED"
    fi
done

if [ "$FOUND_PROJECTS" = false ]; then
    echo "No projects with .devcontainer/devcontainer.json found in $WORKSPACES_DIR" >&2
fi

echo ""
echo "Current project image:"
if [ -f ".devcontainer/devcontainer.json" ]; then
    CURRENT_IMAGE=$(grep -o '"image"[[:space:]]*:[[:space:]]*"[^"]*"' .devcontainer/devcontainer.json | sed 's/.*"image"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "(not found)")
    echo "  $CURRENT_IMAGE"

    # Check version file in container
    if [ -f "/opt/image-version" ]; then
        RUNNING_VERSION=$(cat /opt/image-version)
        echo ""
        echo "Running container version: $RUNNING_VERSION"

        # Compare with devcontainer.json
        if [[ "$CURRENT_IMAGE" == *"$RUNNING_VERSION"* ]]; then
            echo "✅ Container matches devcontainer.json"
        else
            echo "⚠️  Container version mismatch - consider rebuilding" >&2
        fi
    fi
else
    echo "  (no devcontainer.json found)" >&2
fi

echo ""
echo "To upgrade a project:"
echo "  1. Edit .devcontainer/devcontainer.json"
echo "  2. Update the 'image' field to new version"
echo "  3. Rebuild container: Ctrl+Shift+P -> 'Dev Containers: Rebuild Container'"
