###############################################################################
# Stage 1: Build beads (bd) from source with CGO_ENABLED=1
#
# The beads release binaries are built with the gms_pure_go tag on arm64,
# which disables CGO and breaks the embedded Dolt database engine.
# Building from source ensures CGO is enabled on all architectures.
# See: https://github.com/steveyegge/beads/issues/XXX
###############################################################################
FROM golang:1.25-bookworm AS beads-builder
ARG BEADS_VERSION=0.52.0
RUN apt-get update && apt-get install -y --no-install-recommends git gcc g++ libicu-dev && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v${BEADS_VERSION} https://github.com/steveyegge/beads.git /src/beads
WORKDIR /src/beads
# Cache module downloads in their own layer (changes rarely)
RUN go mod download
# Build with cache mounts for Go build cache and module cache.
# This makes rebuilds incremental even when the source layer changes.
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=1 go build -ldflags="-s -w \
    -X main.Version=${BEADS_VERSION} \
    -X main.Commit=$(git rev-parse HEAD) \
    -X main.Branch=$(git rev-parse --abbrev-ref HEAD)" \
    -o /usr/local/bin/bd ./cmd/bd

###############################################################################
# Stage 2: Final image
###############################################################################
FROM debian:bookworm-slim

# Build arguments for external binary versions
ARG GASTOWN_VERSION=0.7.0
ARG DOLT_VERSION=1.82.3
ARG CODEX_VERSION=0.106.0
ARG WRANGLER_VERSION=4.65.0

# Create vscode user, set up locale, and install all system packages in a
# single apt transaction. No build-essential — all compiled binaries come
# from stage 1 or pre-built downloads. Reintroduce if a runtime C compiler
# is ever needed.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    sudo locales \
    ca-certificates gnupg2 openssh-client git curl wget make \
    tmux sqlite3 jq bash-completion procps unzip libicu72 && \
    # --- vscode user ---
    groupadd --gid 1000 vscode && \
    useradd --uid 1000 --gid 1000 -m -s /bin/bash vscode && \
    echo "vscode ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode && \
    # --- locale ---
    sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen && \
    rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Register all external apt repos, then install everything in one pass.
# Node.js is installed as a standalone binary to avoid the NodeSource setup
# script which runs its own apt-get update internally.
RUN ARCH=$(dpkg --print-architecture) && \
    mkdir -p -m 755 /etc/apt/keyrings && \
    # Node.js 20 LTS — direct binary download (avoids NodeSource setup_20.x
    # which adds a repo + runs apt-get update redundantly)
    NODE_VERSION=20.20.0 && \
    NODE_ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" \
      | tar xz --strip-components=1 -C /usr/local && \
    # GitHub CLI
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    # Docker CLI
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
      > /etc/apt/sources.list.d/docker.list && \
    # Doppler CLI
    curl -sLf --retry 3 --tlsv1.2 --proto "=https" \
      'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' | \
      gpg --dearmor -o /etc/apt/keyrings/doppler.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/doppler.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" \
      > /etc/apt/sources.list.d/doppler-cli.list && \
    # Single install for all external apt packages
    apt-get update && apt-get install -y --no-install-recommends \
      gh docker-ce-cli docker-compose-plugin doppler && \
    groupadd -f docker && usermod -aG docker vscode && \
    rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager) to system-wide location
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh && \
    chmod +x /usr/local/bin/uv /usr/local/bin/uvx

# Install Python 3.11 via uv and symlink to /usr/local/bin for all users
ENV UV_PYTHON_INSTALL_DIR="/usr/local/share/uv/python"
RUN uv python install 3.11 && \
    ln -sf $(uv python find 3.11) /usr/local/bin/python3 && \
    ln -sf $(uv python find 3.11) /usr/local/bin/python

# Install Beads binary (built from source in stage 1 with CGO_ENABLED=1)
COPY --from=beads-builder /usr/local/bin/bd /usr/local/bin/bd

# Install Gastown, Dolt, Bun, and Claude Code binaries (single layer)
ENV BUN_INSTALL="/usr/local"
RUN set -e && \
    # Gastown
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    wget -q "https://github.com/steveyegge/gastown/releases/download/v${GASTOWN_VERSION}/gastown_${GASTOWN_VERSION}_linux_${ARCH}.tar.gz" -O /tmp/gastown.tar.gz && \
    tar xzf /tmp/gastown.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/gt && \
    rm /tmp/gastown.tar.gz && \
    # Dolt (SQL server managed by gt for multi-agent beads access)
    wget -q "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-${ARCH}.tar.gz" -O /tmp/dolt.tar.gz && \
    tar xzf /tmp/dolt.tar.gz -C /tmp && \
    mv /tmp/dolt-linux-${ARCH}/bin/dolt /usr/local/bin/dolt && \
    chmod +x /usr/local/bin/dolt && \
    rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-${ARCH} && \
    # Bun
    curl -fsSL https://bun.sh/install | bash && \
    # Claude Code
    GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases" && \
    CC_ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    PLATFORM="linux-${CC_ARCH}" && \
    VERSION=$(curl -fsSL "$GCS_BUCKET/latest") && \
    MANIFEST=$(curl -fsSL "$GCS_BUCKET/$VERSION/manifest.json") && \
    CHECKSUM=$(echo "$MANIFEST" | jq -r ".platforms[\"$PLATFORM\"].checksum") && \
    curl -fsSL -o /tmp/claude "$GCS_BUCKET/$VERSION/$PLATFORM/claude" && \
    echo "$CHECKSUM  /tmp/claude" | sha256sum -c - && \
    mv /tmp/claude /usr/local/bin/claude && \
    chmod +x /usr/local/bin/claude && \
    # Codex CLI
    CODEX_ARCH=$(uname -m) && \
    curl -fsSL -o /tmp/codex.tar.gz \
      "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-${CODEX_ARCH}-unknown-linux-gnu.tar.gz" && \
    tar xzf /tmp/codex.tar.gz -C /tmp && \
    mv /tmp/codex-${CODEX_ARCH}-unknown-linux-gnu /usr/local/bin/codex && \
    chmod +x /usr/local/bin/codex && \
    rm /tmp/codex.tar.gz

# Install JS CLI tools via bun (single layer)
RUN bun install -g wrangler@${WRANGLER_VERSION}

# Ensure Claude config dir exists with correct ownership in the image.
# This prevents root-owned volume initialization on first container start.
RUN mkdir -p /home/vscode/.claude && \
    chown -R vscode:vscode /home/vscode/.claude && \
    chmod 700 /home/vscode/.claude

# Embed all local files (grouped to reduce layers, ordered by change frequency)
COPY docs/UTILITIES.md /usr/local/share/image-docs/UTILITIES.md
COPY docs/.gitattributes /usr/local/share/image-docs/.gitattributes
COPY docs/CLAUDE.md /usr/local/share/image-docs/CLAUDE.md
COPY docs/crew.json /usr/local/share/image-docs/crew.json
COPY lib/ai-coding-utils/slack /opt/ai-coding-utils/slack
COPY lib/ai-coding-utils/beads /opt/ai-coding-utils/beads
COPY lib/agent-configs/claude-agents/ /opt/agent-configs/claude-agents/
COPY lib/agent-configs/github-agents/ /opt/agent-configs/github-agents/
COPY lib/dev-infra/components/ /opt/dev-infra/
COPY lib/dev-infra/secrets /opt/dev-infra/secrets
COPY lib/dev-infra/setup /opt/dev-infra/setup
COPY lib/dev-infra/profile.sh /etc/profile.d/ai-dev-utils.sh
COPY tests/test-tools.sh /usr/local/bin/test-tools.sh

# Add ai-coding-utils to PYTHONPATH (must be set before test-tools.sh runs)
ENV PYTHONPATH="/opt/ai-coding-utils"

# Ensure vscode owns /workspaces so it can create dirs freely (e.g. temp/auth).
# Must precede test-tools.sh which validates this ownership.
RUN mkdir -p /workspaces && chown vscode:vscode /workspaces

# Install Python deps, set permissions, configure shell, validate tools —
# single layer to minimize overhead.
RUN uv pip install --system --break-system-packages --python /usr/local/bin/python3 \
    requests>=2.28.0 pyyaml>=6.0 watchdog>=3.0.0 python-dotenv>=1.0.0 && \
    chmod +x /opt/dev-infra/*.sh /opt/dev-infra/setup/*.sh \
    /opt/ai-coding-utils/beads/setup/ensure_beads.sh \
    /etc/profile.d/ai-dev-utils.sh \
    /usr/local/bin/test-tools.sh && \
    ln -sf /opt/dev-infra/setup/dev-services.sh /usr/local/bin/dev-services && \
    echo '' >> /etc/bash.bashrc && \
    echo '# Source AI dev utilities for all interactive shells' >> /etc/bash.bashrc && \
    echo 'if [ -f /etc/profile.d/ai-dev-utils.sh ]; then' >> /etc/bash.bashrc && \
    echo '    . /etc/profile.d/ai-dev-utils.sh' >> /etc/bash.bashrc && \
    echo 'fi' >> /etc/bash.bashrc && \
    # Validate tools as root and vscode in the same layer
    /usr/local/bin/test-tools.sh && \
    su -c /usr/local/bin/test-tools.sh vscode

# Bake devcontainer metadata into image for VS Code extensions
LABEL devcontainer.metadata='[{ \
  "remoteUser": "vscode", \
  "containerEnv": { \
    "CLAUDE_CONFIG_DIR": "/home/vscode/.claude" \
  }, \
  "mounts": [ \
	"source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind", \
    "source=claude-code-config-${localWorkspaceFolderBasename},target=/home/vscode/.claude,type=volume", \
    "source=gastown-data-${localWorkspaceFolderBasename},target=/home/vscode/gt,type=volume", \
    "source=shared-gh-auth,target=/home/vscode/.shared-auth/gh,type=volume", \
    "source=shared-claude-auth,target=/home/vscode/.shared-auth/claude,type=volume" \
  ], \
  "customizations": { \
    "vscode": { \
      "extensions": [ \
        "ms-azuretools.vscode-docker", \
        "ms-python.python", \
        "charliermarsh.ruff", \
        "RooVeterinaryInc.roo-cline", \
        "sourcegraph.amp", \
        "Anthropic.claude-code", \
        "openai.chatgpt" \
      ], \
      "settings": { \
        "npm.packageManager": "bun" \
      } \
    } \
  }, \
  "postCreateCommand": "cp /usr/local/share/image-docs/UTILITIES.md .devcontainer/UTILITIES.md 2>/dev/null || true; [ ! -f .gitattributes ] && cp /usr/local/share/image-docs/.gitattributes .gitattributes 2>/dev/null || true; [ ! -f CLAUDE.md ] && cp /usr/local/share/image-docs/CLAUDE.md CLAUDE.md 2>/dev/null || true; [ ! -f .devcontainer/crew.json ] && cp /usr/local/share/image-docs/crew.json .devcontainer/crew.json 2>/dev/null || true; /opt/ai-coding-utils/beads/setup/ensure_beads.sh; /opt/dev-infra/setup/ensure_gastown.sh; /opt/dev-infra/setup/ensure_crew.sh; /opt/dev-infra/setup/install-agents.sh", \
  "postStartCommand": "sudo chown -R vscode:vscode /workspaces && dev-services start" \
}]'

WORKDIR /workspaces
CMD ["/bin/bash"]
