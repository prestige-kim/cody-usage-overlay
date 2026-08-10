# Cody Usage Overlay

[![CI](https://github.com/prestige-kim/cody-usage-overlay/actions/workflows/ci.yml/badge.svg)](https://github.com/prestige-kim/cody-usage-overlay/actions/workflows/ci.yml)

An unofficial macOS overlay that displays local Codex Desktop usage counters.
It can follow a visible Cody pet or be moved freely when no pet is shown.

> [!WARNING]
> This is an unofficial community project. It is not affiliated with or
> endorsed by OpenAI. It relies on experimental local Codex interfaces that
> may change without notice.

## Status

The project is currently pre-release software intended for local testing.
Public release binaries are not yet Developer ID signed or notarized.

Current build support:

- macOS 13 or later
- Apple Silicon (`arm64`)
- Codex Desktop installed and signed in

## What it shows

- **Week** — remaining percentage of the weekly Codex rate-limit window.
- **5h** — remaining percentage of the five-hour window when Codex provides it.
- **Context** — estimated remaining context percentage for the most recently
  active root Codex Desktop rollout.

The overlay appears below a detected Cody pet. If no pet is visible, the panel
remains available and can be dragged to a manual position.

## How it works

The account-limit pipeline was informed by
[`GiantForestStudio/codex-weekly-usage-indicator`](https://github.com/GiantForestStudio/codex-weekly-usage-indicator).
The app launches the locally installed `codex app-server --stdio`, initializes
its JSONL protocol, and reads `account/rateLimits/read` plus update
notifications. Context usage is extracted from local Codex Desktop rollout
token events under `~/.codex/sessions`.

No OpenAI API key is required. See [PRIVACY.md](PRIVACY.md) for the exact local
data accessed and retained.

## Build from source

The current developer build requires Swift 6 and the Xcode Command Line Tools.

```bash
./scripts/check.sh
./scripts/build.sh
./scripts/doctor.sh
```

The application bundle is written to `dist/CodyUsageOverlay.app`.

## Install for the current user

Review the scripts before running them:

```bash
./scripts/install.sh
```

This installs:

- App: `~/Applications/CodyUsageOverlay.app`
- Settings: `~/Library/Application Support/CodyUsageOverlay/config.json`
- Logs: `~/Library/Logs/CodyUsageOverlay/`
- Login item: `~/Library/LaunchAgents/com.proudchris.cody-usage-overlay.plist`

Uninstall:

```bash
./scripts/uninstall.sh
./scripts/uninstall.sh --purge  # also removes settings and logs
```

## Configuration

The overlay's context menu provides refresh, position detection, always-on-top,
diagnostics, and quit commands.

The config file is stored at:

```text
~/Library/Application Support/CodyUsageOverlay/config.json
```

`clickThrough` defaults to `false` so the context menu and manual dragging work.

## Known limitations

- `codex app-server` and rollout JSONL formats are experimental and are not
  documented as stable public APIs.
- The active context is inferred from the most recently modified non-subagent
  Codex Desktop rollout.
- The current release build is Apple Silicon only.
- Pet detection depends on local Codex window behavior and can change after a
  Codex Desktop update.
- Direct-download builds are not yet Developer ID signed or notarized.

Run `./scripts/doctor.sh` after a Codex update and include its redacted output in
compatibility reports.

## Security and contributing

- [Security policy](SECURITY.md)
- [Privacy](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Changelog](CHANGELOG.md)

## License

MIT. See [LICENSE](LICENSE).
