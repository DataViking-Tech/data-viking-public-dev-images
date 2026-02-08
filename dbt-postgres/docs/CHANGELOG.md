# Changelog

All notable changes to the dbt-postgres image will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.0.0] - Unreleased

### Added
- Initial release of dbt-postgres devcontainer image
- dbt-core and dbt-postgres installed via uv
- PostgreSQL client (psql) for database interaction
- Extends ai-dev-base:edge (Python 3.11, Claude CLI, beads, Gas Town)
- Validation test script
- CI/CD workflows (edge, PR, release, auto-tag)
