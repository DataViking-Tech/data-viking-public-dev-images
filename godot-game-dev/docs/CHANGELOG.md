# Changelog

All notable changes to the Godot Game Development Base Image will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.0.0] - 2026-01-29

### Added
- Initial release of custom devcontainer image
- Pre-installed Godot 4.5.1 with all dependencies
- Python 3.11 with uv package manager
- Bun 1.1.38 JavaScript runtime
- Claude CLI for AI assistance
- beads (bd) issue tracking CLI
- System packages: ffmpeg, build tools, multimedia libraries
- Image version validation (`/opt/image-version`)
- Tool manifest (`/opt/image-manifest`)
- GitHub Actions workflow for automated builds
- Health check for container validation

### Performance
- Container startup: 5-15 seconds (vs 3-5 min with runtime downloads)
- Image size: ~2.5-3GB
- Build time: ~15-20 minutes (CI)

### Documentation
- README with usage examples
- CHANGELOG (this file)
- UPGRADING guide
- Test validation scripts

---

## Template for Future Releases

## [vX.Y.Z] - YYYY-MM-DD

### Breaking Changes
- Description of breaking changes (if any)
- Migration steps required

### Added
- New tools or features

### Changed
- Updates to existing tools
- Performance improvements

### Deprecated
- Tools or features marked for removal

### Removed
- Removed tools or features

### Fixed
- Bug fixes

### Security
- Security patches or updates

### Performance
- Image size changes
- Build time changes
- Startup time impacts

### Tested With
- List of projects tested with this version
