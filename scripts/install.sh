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
STAGING_DIR=$(mktemp -d "$HOME/Applications/.CodyUsageOverlay.install.XXXXXX")
STAGED_APP="$STAGING_DIR/CodyUsageOverlay.app"
BACKUP_APP="$STAGING_DIR/CodyUsageOverlay.previous.app"
cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT

ditto "$APP_SOURCE" "$STAGED_APP"
xattr -cr "$STAGED_APP"
codesign --force --deep --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

launchctl bootout "gui/$UID/com.proudchris.cody-usage-overlay" 2>/dev/null || true
pkill -x CodyUsageOverlay 2>/dev/null || true
if [[ -e "$APP_DEST" || -L "$APP_DEST" ]]; then mv "$APP_DEST" "$BACKUP_APP"; fi
if ! mv "$STAGED_APP" "$APP_DEST"; then
  if [[ -e "$BACKUP_APP" || -L "$BACKUP_APP" ]]; then mv "$BACKUP_APP" "$APP_DEST"; fi
  exit 1
fi
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then cp "$PROJECT_DIR/Resources/default-config.json" "$CONFIG_DIR/config.json"; fi
sed -e "s|__APP_PATH__|$APP_DEST|g" -e "s|__LOG_DIR__|$LOG_DIR|g" -e "s|__HOME_DIR__|$HOME|g" \
  "$PROJECT_DIR/Resources/com.proudchris.cody-usage-overlay.plist" > "$AGENT_FILE"
launchctl bootstrap "gui/$UID" "$AGENT_FILE"
launchctl kickstart -k "gui/$UID/com.proudchris.cody-usage-overlay"
echo "Installed: $APP_DEST"
