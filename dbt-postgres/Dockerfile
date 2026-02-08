# dbt-postgres Data Engineering Image
# Extends ai-dev-base with dbt-core + dbt-postgres

FROM ghcr.io/dataviking-tech/ai-dev-base:edge

# Metadata
LABEL org.opencontainers.image.source=https://github.com/DataViking-Tech/data-viking-public-dev-images
LABEL org.opencontainers.image.description="Data engineering environment: dbt-core + dbt-postgres + ai-dev-base tools"
LABEL maintainer="DataViking-Tech"

USER root

# PostgreSQL client libs needed by dbt-postgres (psycopg2)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install dbt via uv into the uv-managed Python (not Debian system Python)
# Scripts land in the uv Python's bin dir, so we symlink dbt into /usr/local/bin
RUN uv pip install --system --break-system-packages --python /usr/local/bin/python3 \
    dbt-core \
    dbt-postgres \
    && ln -sf "$(dirname "$(readlink -f /usr/local/bin/python3)")/dbt" /usr/local/bin/dbt

# Copy and run validation script
COPY tests/validate-tools.sh /usr/local/bin/validate-tools.sh
RUN chmod +x /usr/local/bin/validate-tools.sh

# Validate tools as vscode user (catches permission issues before runtime)
USER vscode
RUN /usr/local/bin/validate-tools.sh
USER root

WORKDIR /workspace

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD dbt --version && python3 --version || exit 1

CMD ["/bin/bash"]

USER vscode
