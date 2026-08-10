#!/bin/zsh
set -euo pipefail
PROJECT_DIR=${0:A:h:h}
SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
mkdir -p "$PROJECT_DIR/.build/cache"
SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/cache" \
  swift run --disable-sandbox --package-path "$PROJECT_DIR" CodyUsageCoreChecks
