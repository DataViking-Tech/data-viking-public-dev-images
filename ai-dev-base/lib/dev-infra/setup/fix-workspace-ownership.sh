#!/usr/bin/env bash
# Fix ownership of bind-mounted workspace directories at container create time.
#
# Two-tier approach:
#
#   Tier 1 — chown (Docker on Linux):
#     Works when the workspace is on a Linux ext4 filesystem. The vscode user
#     gains ownership and can create files normally.
#
#   Tier 2 — sudo git submodule init (Podman rootless on Windows):
#     On Windows NTFS mounts, chown is a no-op. Instead, run submodule init as
#     root (which in Podman rootless maps to the actual host user who owns the
#     Windows files). This pre-populates submodule dirs before the project's own
#     postCreateCommand runs, avoiding 'Permission denied' on git submodule clone.
set -uo pipefail

# Tier 1: attempt chown on all workspace dirs (no-op on Windows mounts, silent)
sudo chown -R "$(id -u):$(id -g)" /workspaces 2>/dev/null || true

# Tier 2: for any workspace dir that is still not writable and has submodules,
# init them now as root so the project's postCreateCommand can proceed.
for dir in /workspaces/*/; do
    [ -d "$dir" ]        || continue
    [ -f "$dir/.gitmodules" ] || continue
    [ -w "$dir" ]        && continue  # chown worked — project can do it itself
    echo "[fix-workspace-ownership] ${dir}: not writable, running sudo git submodule update --init --recursive"
    sudo git -C "$dir" submodule update --init --recursive 2>&1 || true
done
