#!/bin/bash
# Example devcontainer startup script with credential caching
#
# The base image's postStartCommand already runs credential setup with
# "github claude" by default. Projects needing different services can
# either:
#
#   Option A: Set CREDENTIAL_CACHE_SERVICES env var in devcontainer.json:
#     "containerEnv": { "CREDENTIAL_CACHE_SERVICES": "github cloudflare" }
#
#   Option B: Call setup_credential_cache directly in a custom script:
#     source /opt/dev-infra/credential_cache.sh
#     setup_credential_cache "github" "cloudflare"
#
# Prerequisites:
#   1. Base image provides dev-infra at /opt/dev-infra/
#   2. Add 'temp/' to .gitignore (REQUIRED for security)
#   3. Make this file executable: chmod +x .devcontainer/postStartCommand.sh

# Source the credential cache component
source /opt/dev-infra/credential_cache.sh

# Setup credentials for services this project needs
# (Only needed if different from base image default of "github claude")
setup_credential_cache "github" "cloudflare"

# Rest of project-specific setup
echo "✓ Container setup complete"
