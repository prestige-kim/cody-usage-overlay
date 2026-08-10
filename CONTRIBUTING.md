# Contributing

Thank you for helping improve Cody Usage Overlay.

## Before opening a change

1. Search existing issues.
2. Keep changes focused and avoid committing Codex logs or session files.
3. Do not add telemetry, account-token access, or outbound networking without
   prior discussion and a corresponding privacy review.
4. Treat `codex app-server` and rollout schemas as experimental interfaces.

## Local checks

```bash
./scripts/check.sh
./scripts/build.sh
codesign --verify --deep --strict --verbose=2 \
  dist/CodyUsageOverlay.app
```

For UI changes, test with the pet enabled and disabled, while dragging, across
Spaces, and on every monitor available to you. Include macOS version, Codex
version, architecture, and relevant doctor output in bug reports. Redact
private paths and identifiers where appropriate.

## Pull requests

- Explain the user-visible behavior and compatibility impact.
- Add or update fixtures for parser and rollout changes.
- Update `CHANGELOG.md` for user-visible changes.
- Do not commit `.build/`, `dist/`, generated archives, credentials, or logs.
