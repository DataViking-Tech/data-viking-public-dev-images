# Godot Game Development Image
# Extends ai-dev-base with game-specific tools

FROM ghcr.io/dataviking-tech/ai-dev-base:edge

# Build arguments for component versions
ARG GODOT_VERSION=4.6.1

# Metadata
LABEL org.opencontainers.image.source=https://github.com/DataViking-Tech/data-viking-public-dev-images
LABEL org.opencontainers.image.description="Game dev environment: Godot ${GODOT_VERSION} + ai-dev-base tools"
LABEL maintainer="DataViking-Tech"

# Switch to root for system package installation
USER root

# Install Godot system dependencies
# (ai-dev-base provides: git, curl, wget, python3, build-essential)
RUN apt-get update && apt-get install -y \
    # Godot runtime dependencies
    libx11-6 libxcursor1 libxinerama1 libxrandr2 libgl1 \
    libegl1 libgles2 libglx0 \
    # Additional Godot libraries
    libfontconfig1 libasound2 libpulse0 \
    libxrender1 libxi6 libxkbcommon0 libxfixes3 \
    libxxf86vm1 libsm6 \
    # Multimedia tools
    ffmpeg \
    # Headless rendering
    xvfb \
    # Utilities
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Godot (arch-aware: x86_64 / arm64)
RUN GODOT_ARCH=$(uname -m | sed 's/aarch64/arm64/') && \
    echo "Installing Godot ${GODOT_VERSION} (${GODOT_ARCH})..." \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip" \
    && unzip -q "Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip" -d /opt \
    && mv "/opt/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}" /opt/godot \
    && chmod +x /opt/godot \
    && ln -s /opt/godot /usr/local/bin/godot \
    && rm "Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip" \
    && godot --version

# Install game-specific Python packages via uv (target Python 3.11 from base image)
# bpy (Blender Python) only publishes x86_64 wheels — install conditionally
COPY .devcontainer/requirements.txt /tmp/requirements.txt
RUN uv pip install --system --break-system-packages --python /usr/local/bin/python3 -r /tmp/requirements.txt && \
    if [ "$(uname -m)" = "x86_64" ]; then \
        uv pip install --system --break-system-packages --python /usr/local/bin/python3 bpy==5.0.1; \
    fi && \
    rm /tmp/requirements.txt

# Install render-bridges (GPU rendering bridge for Linux→Windows host)
COPY lib/render-bridges/render_bridge /opt/render-bridges/render_bridge
COPY lib/render-bridges/godot_render_bridge.py /opt/render-bridges/godot_render_bridge.py
COPY lib/render-bridges/render_bridge_integration.py /opt/render-bridges/render_bridge_integration.py
COPY lib/render-bridges/scripts /opt/render-bridges/scripts
RUN mkdir -p /workspace/temp/render-queue /workspace/temp/render-output \
    && chmod 777 /workspace/temp/render-queue /workspace/temp/render-output

# Make render-bridges importable as a Python module
ENV PYTHONPATH="/opt/render-bridges:${PYTHONPATH}"

# Install dev-infra utilities (enhanced postCreateCommand and image-versions)
COPY lib/dev-infra/postCreateCommand-enhanced.sh /opt/dev-infra/postCreateCommand-enhanced.sh
COPY lib/dev-infra/image-versions.sh /opt/dev-infra/bin/image-versions
RUN chmod +x /opt/dev-infra/postCreateCommand-enhanced.sh /opt/dev-infra/bin/image-versions
ENV PATH="/opt/dev-infra/bin:${PATH}"

# Create symlink for bun/node compatibility (if not in base)
RUN if [ ! -L /usr/local/bin/node ]; then \
        ln -s /usr/local/bin/bun /usr/local/bin/node 2>/dev/null || true; \
    fi

# Append godot-specific utility docs to the base image documentation
COPY docs/UTILITIES.md /tmp/godot-utilities.md
RUN cat /tmp/godot-utilities.md >> /usr/local/share/image-docs/UTILITIES.md && rm /tmp/godot-utilities.md

# Install Claude Code agent configs (generalized game-dev agents)
COPY lib/agent-configs/claude-agents/ /opt/agent-configs/claude-agents/
COPY lib/agent-configs/github-agents/ /opt/agent-configs/github-agents/
COPY lib/agent-configs/roo-rules/ /opt/agent-configs/roo-rules/
COPY lib/agent-configs/copilot-instructions.md /opt/agent-configs/copilot-instructions.md
COPY lib/agent-configs/install-agents.sh /opt/agent-configs/install-agents.sh
RUN chmod +x /opt/agent-configs/install-agents.sh

# Install Godot LSP auto-start script
COPY scripts/godot-lsp-start /usr/local/bin/godot-lsp-start
RUN chmod +x /usr/local/bin/godot-lsp-start

# Copy and run validation script to catch tool access issues at build time
COPY tests/validate-tools.sh /usr/local/bin/validate-tools.sh
RUN chmod +x /usr/local/bin/validate-tools.sh

# Validate tools as vscode user (catches permission issues before runtime)
USER vscode
RUN /usr/local/bin/validate-tools.sh
USER root

# Set working directory
WORKDIR /workspace

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD godot --version && python3 --version || exit 1

# Default shell
CMD ["/bin/bash"]

# Switch user back before exiting
USER vscode
