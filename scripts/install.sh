#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
APP_SOURCE="$PROJECT_DIR/dist/CodyUsageOverlay.app"
APP_DEST="$HOME/Applications/CodyUsageOverlay.app"
CONFIG_DIR="$HOME/Library/Application Support/CodyUsageOverlay"
LOG_DIR="$HOME/Library/Logs/CodyUsageOverlay"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_FILE="$AGENT_DIR/com.proudchris.cody-usage-overlay.plist"

if [[ ! -d "$APP_SOURCE" ]]; then "$PROJECT_DIR/scripts/build.sh" >/dev/null; fi
mkdir -p "$HOME/Applications" "$CONFIG_DIR" "$LOG_DIR" "$AGENT_DIR"
launchctl bootout "gui/$UID/com.proudchris.cody-usage-overlay" 2>/dev/null || true
pkill -x CodyUsageOverlay 2>/dev/null || true
ditto "$APP_SOURCE" "$APP_DEST"
xattr -cr "$APP_DEST"
codesign --force --deep --sign - "$APP_DEST"
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then cp "$PROJECT_DIR/Resources/default-config.json" "$CONFIG_DIR/config.json"; fi
sed -e "s|__APP_PATH__|$APP_DEST|g" -e "s|__LOG_DIR__|$LOG_DIR|g" \
  "$PROJECT_DIR/Resources/com.proudchris.cody-usage-overlay.plist" > "$AGENT_FILE"
launchctl bootstrap "gui/$UID" "$AGENT_FILE"
launchctl kickstart -k "gui/$UID/com.proudchris.cody-usage-overlay"
echo "Installed: $APP_DEST"
