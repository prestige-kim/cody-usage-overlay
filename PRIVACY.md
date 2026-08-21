# Privacy

Cody Usage Overlay is a local macOS utility. It does not include telemetry,
analytics, advertising, or its own outbound HTTP client.

## Local data the app reads

- Rate-limit windows returned by the locally installed experimental Codex
  app-server.
- ChatGPT desktop app Codex rollout files under `~/.codex/sessions` to
  extract session metadata, `last_token_usage.total_tokens`, and
  `model_context_window`.
- ChatGPT window metadata from macOS so the overlay can follow a visible pet.

The rollout reader scans JSONL records in memory and extracts only session
metadata and token counters. Because those files contain other record types,
prompt or response bytes can pass through memory while the reader skips them;
they are not retained, displayed, or transmitted. The app does not persist
message content, account identifiers, authentication tokens, or usage history.
It stores only UI preferences and writes operational logs to
`~/Library/Logs/CodyUsageOverlay/`.

The bundled Codex executable and app-server use the user's existing ChatGPT
desktop installation and authentication. Their behavior is governed by
OpenAI's own terms and privacy practices.

## Diagnostics and bug reports

The “Copy diagnostics” command includes the detected Codex executable path,
active thread identifier, freshness state, and last update time. Review this
text before publishing it.

Do not attach Codex session files, configuration files, authentication tokens,
private logs, or screenshots containing information you do not want to make
public when reporting a bug.
