# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.4] - 2026-08-11

### Added

- Add a close button that hides only the usage window and restores it when the Codex Pet is shown again.

### Changed

- Place the usage window opposite the Codex Pet activity notification and follow its dynamic above/below placement.

### Fixed

- Keep the overlay visible across temporary Codex process-detection failures and macOS Space changes.
- Restart the app automatically after an abnormal exit while preserving intentional quits.

## [0.1.3] - 2026-08-11

### Fixed

- Prefer the canonical `codex` rate-limit bucket when model-specific buckets coexist.
- Read snake-case rate-limit fields from Desktop rollout events.
- Prevent a lagging zero-usage app-server snapshot from overwriting a newer value for the same reset window.

## [0.1.2] - 2026-08-10

### Fixed

- Release checksum files now contain a portable archive filename instead of a GitHub runner path.

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

[Unreleased]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/prestige-kim/cody-usage-overlay/releases/tag/v0.1.0
