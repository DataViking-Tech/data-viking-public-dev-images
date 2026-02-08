# dbt-postgres Dev Container Image

Custom devcontainer image with dbt-core and dbt-postgres for data engineering. Extends `ghcr.io/dataviking-tech/ai-dev-base:edge` which provides core dev tools (Python, Claude, Beads, Gas Town, dev-infra).

## Features

- **dbt-core + dbt-postgres** - Data transformation framework
- **PostgreSQL client** - psql for database interaction
- **Python 3.11 + uv** - Package management
- **Claude CLI** - AI coding assistant
- **beads** - Issue tracking CLI
- **Gas Town (gt)** - Multi-agent workspace manager

## Usage

### In your devcontainer.json

```json
{
  "name": "My dbt Project",
  "image": "ghcr.io/dataviking-tech/dbt-postgres:edge",

  "customizations": {
    "vscode": {
      "extensions": [
        "innoverio.vscode-dbt-power-user"
      ]
    }
  }
}
```

## Building Locally

```bash
docker build -t dbt-postgres:local -f dbt-postgres/Dockerfile dbt-postgres/
docker run -it dbt-postgres:local bash
```

## Documentation

- [CHANGELOG](docs/CHANGELOG.md) - Version history
