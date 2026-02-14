# Project Development Guide

> Default CLAUDE.md from ai-dev-base-image. Override by editing this file.

## Session Startup

If Gas Town is installed (`gt` command available), always run at session start:

```bash
gt prime
```

This loads your role context, beads workflow, and any hooked work.

## Gas Town Workflow (when active)

When this project is managed by Gas Town (`~/gt/` exists):

### Mayor Role (coordinator in /workspaces/)
- **Do NOT implement code changes directly** - dispatch to polecats via `gt sling`
- Use `bd` commands for issue tracking (beads are in `~/gt/<rig>/.beads/`, NOT in the project root)
- Coordinate work, review PR results, manage priorities

### Polecat Role (worker in ~/gt/<rig>/polecats/)
- Work through molecule steps: `bd ready` / `bd close <step>`
- Commit frequently with atomic changes
- Run `gt done` when complete (mandatory, no exceptions)

### Key Rules
1. **Check your role**: `echo $GT_ROLE` - mayor coordinates, polecats implement
2. **Beads location**: Always use `bd` commands (BEADS_DIR is set automatically)
3. **Never push to main directly** - use `gt done` for merge queue or create PRs
4. **If stuck >15 min**: Escalate via `gt escalate` or mail the Witness

## Without Gas Town

If Gas Town is not active, work directly in the project:
- Use `bd` for issue tracking if available
- Follow the project's existing contribution guidelines
- Run tests before committing
