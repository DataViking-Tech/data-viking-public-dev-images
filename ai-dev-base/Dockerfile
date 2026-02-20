FROM debian:bookworm-slim

# Build arguments for external binary versions
ARG BEADS_VERSION=0.49.3
ARG GASTOWN_VERSION=0.5.0
ARG CLAUDE_CODE_VERSION=2.1.41
ARG CODEX_VERSION=0.101.0
ARG WRANGLER_VERSION=4.65.0

# Create vscode user with sudo access (replaces devcontainers base)
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo && \
    groupadd --gid 1000 vscode && \
    useradd --uid 1000 --gid 1000 -m -s /bin/bash vscode && \
    echo "vscode ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode && \
    rm -rf /var/lib/apt/lists/*

# Set up locale (bookworm-slim has none)
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales && \
    sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Install system dependencies (excluding nodejs - installed separately below)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    gnupg2 \
    openssh-client \
    git \
    curl \
    wget \
    build-essential \
    tmux \
    sqlite3 \
    jq \
    bash-completion \
    procps \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20 LTS via NodeSource (wrangler requires Node 20+)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN (type -p wget >/dev/null || (apt-get update && apt-get install -y wget)) && \
    mkdir -p -m 755 /etc/apt/keyrings && \
    out=$(mktemp) && wget -qO "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg && \
    cat "$out" | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install Docker CLI + Compose plugin (no daemon — uses host socket via mount)
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" | \
    tee /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    docker-ce-cli \
    docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -f docker && usermod -aG docker vscode

# Install Doppler CLI (secrets management)
RUN curl -sLf --retry 3 --tlsv1.2 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' | \
    gpg --dearmor -o /etc/apt/keyrings/doppler.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/doppler.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" | \
    tee /etc/apt/sources.list.d/doppler-cli.list && \
    apt-get update && apt-get install -y doppler && \
    rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager) to system-wide location
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh && \
    chmod +x /usr/local/bin/uv /usr/local/bin/uvx

# Install Python 3.11 via uv and symlink to /usr/local/bin for all users
ENV UV_PYTHON_INSTALL_DIR="/usr/local/share/uv/python"
RUN uv python install 3.11 && \
    ln -sf $(uv python find 3.11) /usr/local/bin/python3 && \
    ln -sf $(uv python find 3.11) /usr/local/bin/python

# Install Beads binary
RUN wget -q https://github.com/steveyegge/beads/releases/download/v${BEADS_VERSION}/beads_${BEADS_VERSION}_linux_amd64.tar.gz -O /tmp/beads.tar.gz && \
    tar xzf /tmp/beads.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/bd && \
    rm /tmp/beads.tar.gz

# Install Gastown binary
RUN wget -q https://github.com/steveyegge/gastown/releases/download/v${GASTOWN_VERSION}/gastown_${GASTOWN_VERSION}_linux_amd64.tar.gz -O /tmp/gastown.tar.gz && \
    tar xzf /tmp/gastown.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/gt && \
    rm /tmp/gastown.tar.gz

# Install Bun to system-wide location (accessible by all users including vscode)
ENV BUN_INSTALL="/usr/local"
RUN curl -fsSL https://bun.sh/install | bash

# Install Claude Code CLI via native installer and symlink to system PATH
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && ln -sf /root/.claude/bin/claude /usr/local/bin/claude

# Install OpenAI Codex CLI globally (bun puts globals in $BUN_INSTALL/bin)
RUN bun install -g @openai/codex@${CODEX_VERSION}

# Install Wrangler (Cloudflare CLI) globally
RUN bun install -g wrangler@${WRANGLER_VERSION}

# Embed ai-coding-utils (slack notifications + beads hooks)
COPY lib/ai-coding-utils/slack /opt/ai-coding-utils/slack
COPY lib/ai-coding-utils/beads /opt/ai-coding-utils/beads

# Install Python dependencies for embedded libraries
RUN uv pip install --system --break-system-packages --python /usr/local/bin/python3 \
    requests>=2.28.0 \
    pyyaml>=6.0 \
    watchdog>=3.0.0 \
    python-dotenv>=1.0.0

# Add ai-coding-utils to PYTHONPATH
ENV PYTHONPATH="/opt/ai-coding-utils"

# Embed Claude agent configurations for downstream projects
COPY lib/agent-configs/claude-agents/ /opt/agent-configs/claude-agents/

# Embed agent configs (GitHub Copilot workspace agents)
COPY lib/agent-configs/github-agents/ /opt/agent-configs/github-agents/

# Embed dev-infra (devcontainer components, secrets manager, project setup)
COPY lib/dev-infra/components/ /opt/dev-infra/
COPY lib/dev-infra/secrets /opt/dev-infra/secrets
COPY lib/dev-infra/setup /opt/dev-infra/setup
RUN chmod +x /opt/dev-infra/*.sh /opt/dev-infra/setup/*.sh \
    && chmod +x /opt/ai-coding-utils/beads/setup/ensure_beads.sh \
    && chmod +x /opt/dev-infra/setup/ensure_gastown.sh \
    && chmod +x /opt/dev-infra/setup/ensure_crew.sh \
    && chmod +x /opt/dev-infra/setup/start_gastown_services.sh \
    && chmod +x /opt/dev-infra/setup/start_beads_notifier.sh \
    && chmod +x /opt/dev-infra/setup/daemon_watchdog.sh

# Copy utility documentation and defaults into the image for downstream layering
COPY docs/UTILITIES.md /usr/local/share/image-docs/UTILITIES.md
COPY docs/.gitattributes /usr/local/share/image-docs/.gitattributes
COPY docs/CLAUDE.md /usr/local/share/image-docs/CLAUDE.md
COPY docs/crew.json /usr/local/share/image-docs/crew.json

# Copy auto-source script
COPY lib/dev-infra/profile.sh /etc/profile.d/ai-dev-utils.sh
RUN chmod +x /etc/profile.d/ai-dev-utils.sh

# Source ai-dev-utils.sh from bash.bashrc so non-login interactive shells get functions too
RUN echo '' >> /etc/bash.bashrc && \
    echo '# Source AI dev utilities for all interactive shells' >> /etc/bash.bashrc && \
    echo 'if [ -f /etc/profile.d/ai-dev-utils.sh ]; then' >> /etc/bash.bashrc && \
    echo '    . /etc/profile.d/ai-dev-utils.sh' >> /etc/bash.bashrc && \
    echo 'fi' >> /etc/bash.bashrc

# Copy and run test script
COPY tests/test-tools.sh /usr/local/bin/test-tools.sh
RUN chmod +x /usr/local/bin/test-tools.sh && \
    /usr/local/bin/test-tools.sh

# Validate tools are accessible as the vscode user (catches permission issues)
USER vscode
RUN /usr/local/bin/test-tools.sh
USER root

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
  "postStartCommand": "/opt/dev-infra/setup/start_gastown_services.sh; /opt/dev-infra/setup/start_beads_notifier.sh" \
}]'

# Set working directory
WORKDIR /workspace

# Default shell
CMD ["/bin/bash"]
