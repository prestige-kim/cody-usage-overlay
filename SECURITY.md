# Security Policy

## Reporting a vulnerability

Use GitHub private vulnerability reporting for security-sensitive issues when
it is available for this repository. Use public issues only for ordinary bugs.

Do not include credentials, authentication tokens, Codex session contents,
private Codex logs, or personal account information in a report.

## Trust and release verification

This project is an unofficial community utility. It launches the locally
installed Codex app-server and reads token counters from local Codex session
files. It does not require an OpenAI API key.

Until a release is explicitly marked as Developer ID signed and notarized,
release binaries must be treated as unsigned test builds. Verify published
SHA-256 checksums or build from source. Never disable macOS security controls
globally to run this app.

Supported versions and known compatibility issues will be documented in each
GitHub release. The experimental Codex app-server protocol may change without
notice.
