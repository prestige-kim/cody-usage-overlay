# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-08-10

### Added

- Self-contained release archive with install and uninstall commands.

### Changed

- Release packaging now includes the LaunchAgent and default configuration required for source-free installation.

## [0.1.0] - 2026-08-10

### Added

- Local macOS usage overlay for Codex Desktop.
- Remaining weekly and optional five-hour rate-limit display.
- Active Desktop session context-window estimate.
- Cody pet anchoring with a movable fallback when no pet is visible.
- Per-user LaunchAgent installation, diagnostics, and uninstall scripts.

### Known limitations

- Experimental, undocumented Codex app-server and rollout schemas.
- Apple Silicon release build only.
- Release binaries are not yet Developer ID signed or notarized.

[Unreleased]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/prestige-kim/cody-usage-overlay/releases/tag/v0.1.0
