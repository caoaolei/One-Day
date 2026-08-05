#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
BUILD_PATH="$PROJECT_ROOT/.build"
CACHE_PATH="$PROJECT_ROOT/.swiftpm-cache"
APP_PATH="$PROJECT_ROOT/dist/一日.app"
CONTENTS_PATH="$APP_PATH/Contents"

env \
  SDKROOT="$SDK_PATH" \
  CLANG_MODULE_CACHE_PATH="$BUILD_PATH/module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_PATH/module-cache" \
  /usr/bin/swift build \
    -c release \
    --scratch-path "$BUILD_PATH" \
    --cache-path "$CACHE_PATH"

mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
cp "$BUILD_PATH/arm64-apple-macosx/release/YiRi" "$CONTENTS_PATH/MacOS/YiRi"
cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS_PATH/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$CONTENTS_PATH/Resources/AppIcon.icns"
chmod +x "$CONTENTS_PATH/MacOS/YiRi"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "$APP_PATH"
