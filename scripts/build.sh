#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/CodyUsageOverlay.app"

if [[ ! -d "$SDK_PATH" ]]; then
  SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$BUILD_DIR/cache" "$PROJECT_DIR/dist"
SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$BUILD_DIR/cache" \
  swift build --disable-sandbox -c release --package-path "$PROJECT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/arm64-apple-macosx/release/CodyUsageOverlay" "$APP_DIR/Contents/MacOS/CodyUsageOverlay"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/codex-emoji.png" "$APP_DIR/Contents/Resources/codex-emoji.png"
for attempt in 1 2 3; do
  xattr -cr "$APP_DIR"
  if codesign --force --deep --sign - "$APP_DIR"; then
    break
  fi
  if [[ "$attempt" == 3 ]]; then exit 1; fi
done
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
echo "$APP_DIR"
