#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
APP_SOURCE="$PROJECT_DIR/dist/CodyUsageOverlay.app"
OUTPUT_DIR=${1:-$PROJECT_DIR/dist}
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cody-usage-release.XXXXXX")
PACKAGE_NAME="CodyUsageOverlay-$VERSION-arm64"
PACKAGE_DIR="$STAGING_DIR/$PACKAGE_NAME"
ARCHIVE="$OUTPUT_DIR/$PACKAGE_NAME.zip"

cleanup() { rm -rf "$STAGING_DIR"; }
trap cleanup EXIT

if [[ ! -d "$APP_SOURCE" ]]; then
  "$PROJECT_DIR/scripts/build.sh" >/dev/null
fi

APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SOURCE/Contents/Info.plist")
[[ "$APP_VERSION" == "$VERSION" ]] || {
  echo "App version $APP_VERSION does not match source version $VERSION" >&2
  exit 1
}

mkdir -p "$PACKAGE_DIR/dist" "$PACKAGE_DIR/scripts" "$PACKAGE_DIR/Resources" "$OUTPUT_DIR"
ditto "$APP_SOURCE" "$PACKAGE_DIR/dist/CodyUsageOverlay.app"
cp "$PROJECT_DIR/scripts/Install.command" "$PACKAGE_DIR/Install.command"
cp "$PROJECT_DIR/scripts/Uninstall.command" "$PACKAGE_DIR/Uninstall.command"
cp "$PROJECT_DIR/scripts/Doctor.command" "$PACKAGE_DIR/Doctor.command"
cp "$PROJECT_DIR/scripts/install.sh" "$PACKAGE_DIR/scripts/install.sh"
cp "$PROJECT_DIR/scripts/uninstall.sh" "$PACKAGE_DIR/scripts/uninstall.sh"
cp "$PROJECT_DIR/scripts/doctor.sh" "$PACKAGE_DIR/scripts/doctor.sh"
cp "$PROJECT_DIR/scripts/doctor.py" "$PACKAGE_DIR/scripts/doctor.py"
cp "$PROJECT_DIR/Resources/default-config.json" "$PACKAGE_DIR/Resources/default-config.json"
cp "$PROJECT_DIR/Resources/com.proudchris.cody-usage-overlay.plist" "$PACKAGE_DIR/Resources/com.proudchris.cody-usage-overlay.plist"
cp "$PROJECT_DIR/README.md" "$PACKAGE_DIR/README.md"
cp "$PROJECT_DIR/LICENSE" "$PACKAGE_DIR/LICENSE"
chmod +x "$PACKAGE_DIR/Install.command" "$PACKAGE_DIR/Uninstall.command" "$PACKAGE_DIR/Doctor.command" "$PACKAGE_DIR/scripts/"*.sh "$PACKAGE_DIR/scripts/doctor.py"
xattr -cr "$PACKAGE_DIR"
codesign --verify --deep --strict --verbose=2 "$PACKAGE_DIR/dist/CodyUsageOverlay.app"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ARCHIVE"
CHECKSUM=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
printf "%s  %s\n" "$CHECKSUM" "${ARCHIVE:t}" > "$ARCHIVE.sha256"
echo "$ARCHIVE"
