#!/bin/zsh
set -euo pipefail

PURGE=false
[[ ${1:-} == "--purge" ]] && PURGE=true
launchctl bootout "gui/$UID/com.proudchris.cody-usage-overlay" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.proudchris.cody-usage-overlay.plist"
rm -rf "$HOME/Applications/CodyUsageOverlay.app"
if $PURGE; then
  rm -rf "$HOME/Library/Application Support/CodyUsageOverlay" "$HOME/Library/Logs/CodyUsageOverlay"
fi
echo "Cody Usage Overlay removed."
