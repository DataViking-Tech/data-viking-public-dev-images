# Credential Cache Integration Examples

Reference configurations showing how to integrate the credential cache component.

## Files

- `devcontainer.json` - Example devcontainer configuration with required mounts
- `postStartCommand.sh` - Example startup script using credential cache

## Usage

dev-infra components are pre-installed at `/opt/dev-infra/` in the base image.

1. Copy example files to your project's `.devcontainer/` directory and adapt for your project.

2. Add `temp/` to your `.gitignore` (REQUIRED)

See [../README.md](../README.md) for complete documentation.
