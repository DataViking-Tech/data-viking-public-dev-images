###############################################################################
# Stage 1: Build beads (bd) from source with CGO_ENABLED=1
#
# The beads release binaries are built with the gms_pure_go tag on arm64,
# which disables CGO and breaks the embedded Dolt database engine.
# Building from source ensures CGO is enabled on all architectures.
# See: https://github.com/steveyegge/beads/pull/1 (arm64 CGO fix)
###############################################################################
FROM golang:1.26-bookworm@sha256:8e8aa801e8417ef0b5c42b504dd34db3db911bb73dba933bd8bde75ed815fdbb AS beads-builder
ARG BEADS_VERSION=1.0.0
RUN apt-get update && apt-get install -y --no-install-recommends git gcc g++ libicu-dev && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v${BEADS_VERSION} https://github.com/steveyegge/beads.git /src/beads || \
    (sleep 2 && git clone --depth 1 --branch v${BEADS_VERSION} https://github.com/steveyegge/beads.git /src/beads) || \
    (sleep 5 && git clone --depth 1 --branch v${BEADS_VERSION} https://github.com/steveyegge/beads.git /src/beads)
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
# Stage 1b: Build Gas City (gc) from source with patched deps
#
# The upstream release binary currently fails Trivy due to embedded Go stdlib
# and transitive dependency CVEs. Building from source with the current Go
# toolchain and a patched jsonparser dependency avoids those findings while
# keeping the pinned Gas City release tag.
###############################################################################
FROM golang:1.26-bookworm@sha256:8e8aa801e8417ef0b5c42b504dd34db3db911bb73dba933bd8bde75ed815fdbb AS gascity-builder
ARG GASCITY_VERSION=0.13.4
RUN apt-get update && apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v${GASCITY_VERSION} https://github.com/gastownhall/gascity.git /src/gascity || \
    (sleep 2 && git clone --depth 1 --branch v${GASCITY_VERSION} https://github.com/gastownhall/gascity.git /src/gascity) || \
    (sleep 5 && git clone --depth 1 --branch v${GASCITY_VERSION} https://github.com/gastownhall/gascity.git /src/gascity)
WORKDIR /src/gascity
RUN go get github.com/buger/jsonparser@v1.1.2 && go mod download
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /usr/local/bin/gc ./cmd/gc

###############################################################################
# Stage 1c: Build Gas Town from source
#
# As of v1.0.0, the upstream GitHub release no longer ships pre-built linux
# tarballs (the v1.0.0 release at gastownhall/gastown has zero binary assets).
# We mirror the gascity-builder pattern and build gt from source — which is
# also what the official Homebrew formula does.
###############################################################################
FROM golang:1.26-bookworm@sha256:8e8aa801e8417ef0b5c42b504dd34db3db911bb73dba933bd8bde75ed815fdbb AS gastown-builder
ARG GASTOWN_VERSION=1.0.0
RUN apt-get update && apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v${GASTOWN_VERSION} https://github.com/gastownhall/gastown.git /src/gastown || \
    (sleep 2 && git clone --depth 1 --branch v${GASTOWN_VERSION} https://github.com/gastownhall/gastown.git /src/gastown) || \
    (sleep 5 && git clone --depth 1 --branch v${GASTOWN_VERSION} https://github.com/gastownhall/gastown.git /src/gastown)
WORKDIR /src/gastown
RUN go mod download
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 go build \
      -ldflags="-s -w \
        -X github.com/steveyegge/gastown/internal/cmd.Version=${GASTOWN_VERSION} \
        -X github.com/steveyegge/gastown/internal/cmd.Branch=v${GASTOWN_VERSION}" \
      -o /usr/local/bin/gt ./cmd/gt

###############################################################################
# Stage 2: Final image
###############################################################################
FROM debian:bookworm-slim@sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a

# Build arguments for external binary versions
ARG GASTOWN_VERSION=1.0.0
ARG GASCITY_VERSION=0.13.4
ARG DOLT_VERSION=1.88.0
ARG CLAUDE_CODE_VERSION=2.1.81
ARG CODEX_VERSION=0.116.0
ARG UV_VERSION=0.7.12
ARG BUN_VERSION=1.2.9
ARG WRANGLER_VERSION=4.76.0

# Create vscode user, set up locale, and install all system packages in a
# single apt transaction. No build-essential — all compiled binaries come
# from stage 1 or pre-built downloads. Reintroduce if a runtime C compiler
# is ever needed.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    sudo locales \
    ca-certificates gnupg2 openssh-client git curl wget make \
    gcc g++ libicu-dev util-linux \
    tmux sqlite3 jq bash-completion procps unzip libicu72 postgresql-client \
    # Playwright/Chromium headless deps (avoids npx playwright install-deps at runtime)
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 \
    libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 \
    libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
    libxfixes3 libxkbcommon0 libxrandr2 xvfb \
    fonts-noto-color-emoji fonts-unifont libfontconfig1 libfreetype6 \
    xfonts-scalable fonts-liberation fonts-ipafont-gothic fonts-wqy-zenhei \
    fonts-tlwg-loma-otf fonts-freefont-ttf && \
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
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -o /tmp/node.tar.gz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" && \
    NODE_SHA=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | \
      grep "node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" | awk '{print $1}') && \
    echo "${NODE_SHA}  /tmp/node.tar.gz" | sha256sum -c - && \
    tar xz --strip-components=1 -C /usr/local < /tmp/node.tar.gz && \
    rm /tmp/node.tar.gz && \
    npm install -g npm@latest && \
    # GitHub CLI
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    # Docker CLI
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
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
RUN UV_ARCH=$(uname -m) && \
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -o /tmp/uv.tar.gz \
      "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" && \
    UV_SHA=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz.sha256" | awk '{print $1}') && \
    echo "${UV_SHA}  /tmp/uv.tar.gz" | sha256sum -c - && \
    mkdir /tmp/uv-extract && \
    tar xzf /tmp/uv.tar.gz -C /tmp/uv-extract --strip-components=1 && \
    install -m755 /tmp/uv-extract/uv /tmp/uv-extract/uvx /usr/local/bin/ && \
    rm -rf /tmp/uv.tar.gz /tmp/uv-extract

# Install Python 3.11 via uv and symlink to /usr/local/bin for all users
ENV UV_PYTHON_INSTALL_DIR="/usr/local/share/uv/python"
RUN uv python install 3.11 && \
    ln -sf $(uv python find 3.11) /usr/local/bin/python3 && \
    ln -sf $(uv python find 3.11) /usr/local/bin/python

# Install Go runtime (needed for rebuilding gt/beads from source at runtime)
COPY --from=beads-builder /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Install Beads binary (built from source in stage 1 with CGO_ENABLED=1)
COPY --from=beads-builder /usr/local/bin/bd /usr/local/bin/bd

# Install Gas City binary (built from source in stage 1b)
COPY --from=gascity-builder /usr/local/bin/gc /usr/local/bin/gc

# Install Gas Town binary (built from source in stage 1c — see comment on
# the gastown-builder stage above for why we no longer wget the release tarball)
COPY --from=gastown-builder /usr/local/bin/gt /usr/local/bin/gt

# Install Dolt, Bun, and Claude Code binaries (single layer)
ENV BUN_INSTALL="/usr/local"
RUN set -e && \
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    # Dolt (SQL server managed by gt for multi-agent beads access)
    DOLT_SHA=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://api.github.com/repos/dolthub/dolt/releases/tags/v${DOLT_VERSION}" | \
      jq -r ".assets[] | select(.name == \"dolt-linux-${ARCH}.tar.gz\") | .digest" | sed 's/sha256://') && \
    wget -q --tries=3 --waitretry=2 "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-${ARCH}.tar.gz" -O /tmp/dolt.tar.gz && \
    echo "${DOLT_SHA}  /tmp/dolt.tar.gz" | sha256sum -c - && \
    tar xzf /tmp/dolt.tar.gz -C /tmp && \
    mv /tmp/dolt-linux-${ARCH}/bin/dolt /usr/local/bin/dolt && \
    chmod +x /usr/local/bin/dolt && \
    rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-${ARCH} && \
    # Bun
    BUN_ARCH=$(uname -m | sed 's/x86_64/x64/') && \
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -o /tmp/bun.zip \
      "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${BUN_ARCH}.zip" && \
    BUN_SHA=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt" | \
      grep "bun-linux-${BUN_ARCH}.zip$" | awk '{print $1}') && \
    echo "${BUN_SHA}  /tmp/bun.zip" | sha256sum -c - && \
    unzip -q /tmp/bun.zip -d /tmp/bun-extract && \
    install -m755 /tmp/bun-extract/bun-linux-${BUN_ARCH}/bun /usr/local/bin/bun && \
    ln -sf /usr/local/bin/bun /usr/local/bin/bunx && \
    rm -rf /tmp/bun.zip /tmp/bun-extract && \
    # Claude Code
    GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases" && \
    CC_ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    PLATFORM="linux-${CC_ARCH}" && \
    VERSION="${CLAUDE_CODE_VERSION}" && \
    MANIFEST=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$GCS_BUCKET/$VERSION/manifest.json") && \
    CHECKSUM=$(echo "$MANIFEST" | jq -r ".platforms[\"$PLATFORM\"].checksum") && \
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors -o /tmp/claude "$GCS_BUCKET/$VERSION/$PLATFORM/claude" && \
    echo "$CHECKSUM  /tmp/claude" | sha256sum -c - && \
    mv /tmp/claude /usr/local/bin/claude && \
    chmod +x /usr/local/bin/claude && \
    # Codex CLI
    CODEX_ARCH=$(uname -m) && \
    CODEX_SHA=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://api.github.com/repos/openai/codex/releases/tags/rust-v${CODEX_VERSION}" | \
      jq -r ".assets[] | select(.name == \"codex-${CODEX_ARCH}-unknown-linux-gnu.tar.gz\") | .digest" | sed 's/sha256://') && \
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors -o /tmp/codex.tar.gz \
      "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-${CODEX_ARCH}-unknown-linux-gnu.tar.gz" && \
    echo "${CODEX_SHA}  /tmp/codex.tar.gz" | sha256sum -c - && \
    tar xzf /tmp/codex.tar.gz -C /tmp && \
    mv /tmp/codex-${CODEX_ARCH}-unknown-linux-gnu /usr/local/bin/codex && \
    chmod +x /usr/local/bin/codex && \
    rm /tmp/codex.tar.gz && \
    # Amp CLI
    AMP_PLATFORM=$(uname -m | sed 's/x86_64/linux-x64/;s/aarch64/linux-arm64/') && \
    AMP_VERSION=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://storage.googleapis.com/amp-public-assets-prod-0/cli/cli-version.txt") && \
    AMP_SHA=$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      "https://storage.googleapis.com/amp-public-assets-prod-0/cli/${AMP_VERSION}/${AMP_PLATFORM}-amp.sha256") && \
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -o /tmp/amp \
      "https://storage.googleapis.com/amp-public-assets-prod-0/cli/${AMP_VERSION}/amp-${AMP_PLATFORM}" && \
    echo "${AMP_SHA}  /tmp/amp" | sha256sum -c - && \
    install -m755 /tmp/amp /usr/local/bin/amp && \
    rm /tmp/amp

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
COPY lib/llm-tools/ /opt/llm-tools/
COPY lib/dev-infra/env_hydrate.sh /opt/dev-infra/env_hydrate.sh
COPY lib/dev-infra/setup /opt/dev-infra/setup
COPY lib/dev-infra/cli /opt/dev-infra/cli
COPY lib/dev-infra/profile.sh /etc/profile.d/ai-dev-utils.sh
COPY tests/test-tools.sh /usr/local/bin/test-tools.sh

# Add ai-coding-utils to PYTHONPATH (must be set before test-tools.sh runs)
ENV PYTHONPATH="/opt/ai-coding-utils"

# Ensure vscode owns /workspaces so it can create dirs freely (e.g. temp/auth).
# Must precede test-tools.sh which validates this ownership.
RUN mkdir -p /workspaces && chown vscode:vscode /workspaces

# Trust all repos in the container. Bind mounts appear root-owned; Git's
# ownership check is a multi-user safety guard that doesn't apply in a
# single-user disposable devcontainer.
RUN git config --system --add safe.directory '*'

# Install Python deps, set permissions, configure shell, validate tools —
# single layer to minimize overhead.
RUN uv pip install --system --break-system-packages --python /usr/local/bin/python3 \
    requests>=2.28.0 pyyaml>=6.0 watchdog>=3.0.0 python-dotenv>=1.0.0 \
    "setuptools>=78.1.1" "wheel>=0.46.2" "jaraco.context>=6.1.0" && \
    chmod +x /opt/llm-tools/* && \
    ln -sf /opt/llm-tools/* /usr/local/bin/ && \
    chmod +x /opt/dev-infra/*.sh /opt/dev-infra/setup/*.sh \
    /opt/dev-infra/cli/*.sh \
    /opt/ai-coding-utils/beads/setup/ensure_beads.sh \
    /etc/profile.d/ai-dev-utils.sh \
    /usr/local/bin/test-tools.sh && \
    ln -sf /opt/dev-infra/setup/dev-services.sh /usr/local/bin/dev-services && \
    ln -sf /opt/dev-infra/cli/dop.sh /usr/local/bin/dop && \
    ln -sf /opt/dev-infra/cli/supa-query.sh /usr/local/bin/supa-query && \
    ln -sf /opt/dev-infra/cli/dagster-cloud.sh /usr/local/bin/dagster-cloud && \
    ln -sf /opt/dev-infra/cli/dbx.sh /usr/local/bin/dbx && \
    ln -sf /opt/dev-infra/cli/cf.sh /usr/local/bin/cf && \
    ln -sf /opt/dev-infra/cli/cf-r2.sh /usr/local/bin/cf-r2 && \
    ln -sf /opt/dev-infra/cli/kafka-rest.sh /usr/local/bin/kafka-rest && \
    ln -sf /opt/dev-infra/cli/gmail.sh /usr/local/bin/gmail && \
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
  "postCreateCommand": "/opt/dev-infra/setup/fix-workspace-ownership.sh && cp /usr/local/share/image-docs/UTILITIES.md .devcontainer/UTILITIES.md 2>/dev/null || true && [ ! -f .gitattributes ] && cp /usr/local/share/image-docs/.gitattributes .gitattributes 2>/dev/null || true && [ ! -f CLAUDE.md ] && cp /usr/local/share/image-docs/CLAUDE.md CLAUDE.md 2>/dev/null || true && [ ! -f .devcontainer/crew.json ] && cp /usr/local/share/image-docs/crew.json .devcontainer/crew.json 2>/dev/null || true && /opt/ai-coding-utils/beads/setup/ensure_beads.sh && /opt/dev-infra/setup/ensure_gastown.sh && /opt/dev-infra/setup/ensure_crew.sh && /opt/dev-infra/setup/install-agents.sh", \
  "postStartCommand": "dev-services start" \
}]'

USER vscode
WORKDIR /workspaces
CMD ["/bin/bash"]
