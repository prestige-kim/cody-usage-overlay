# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.2] - 2026-08-21

### Changed

- Document the unified ChatGPT desktop app as the required desktop client.
- Remove legacy standalone Codex desktop application paths while retaining the official Codex CLI as a fallback.
- Correct the macOS installation guidance to use OpenAI's current direct download; Windows continues to use Microsoft Store/MSIX discovery.
- Detect the native-composition pet panel used by current ChatGPT builds and debounce transient window candidates.
- Decouple overlay visibility from pet-window detection, reduce window polling to 10 Hz, and keep the last reliable anchor through short detection gaps.
- Replace the ambiguous menu-bar chart with a paw icon and document how to relaunch after an intentional quit.
- Clarify the local rollout scanning behavior and add checksum and first-launch guidance for macOS users.

### Added

- Add a persistent menu-bar control for showing the overlay, following Cody, click-through, always-on-top, and position reset.
- Persist fixed positions and user-adjusted offsets while following Cody.

### Fixed

- Prevent the overlay from reappearing or staying hidden because a transient pet detection result changed.
- Keep the overlay draggable in both fixed and follow modes and apply the previously unused vertical offset.
- Decode existing configuration files when newer optional settings are absent.
- Preserve partial JSONL records across filesystem events and reset the reader after rollout truncation.
- Serialize rate-limit refreshes and keep only one exponential-backoff retry pending.
- Stage and verify macOS updates before replacing the installed app so removed bundle files cannot linger.

## [0.2.1] - 2026-08-14

### Added

- Discover the bundled Codex executable in the unified ChatGPT desktop app and Microsoft Store/MSIX package.
- Report Store package locations and desktop process executable paths in the Windows doctor output.

### Changed

- Preserve standalone CLI lookup paths as fallbacks after process and Store package discovery.

## [0.2.0] - 2026-08-13

### Added

- Add an experimental Windows 11 x64 WPF overlay with the same Week, optional 5h, and Context data pipeline.
- Add Win32 pet/activity discovery, event-driven positioning, PowerShell management scripts, and Windows CI packaging.

### Changed

- Publish macOS and Windows packages from one shared versioned release workflow.

## [0.1.5] - 2026-08-11

### Added

- Include `Doctor.command` in release archives for post-install compatibility checks.
- Search system and user application folders plus common Homebrew and user CLI paths for Codex.

### Changed

- Identify Codex windows by bundle process ID with flexible owner-name and activity-window fallbacks.
- Convert Quartz coordinates using the primary display geometry for vertically arranged monitors.
- Set the documented requirement to macOS 14 to match the current Codex-capable ChatGPT app.

### Fixed

- Prevent the doctor from waiting indefinitely when app-server does not respond.
- Give the login LaunchAgent access to common Codex CLI locations.

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

[Unreleased]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/prestige-kim/cody-usage-overlay/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/prestige-kim/cody-usage-overlay/releases/tag/v0.1.0
