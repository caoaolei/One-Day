#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
BUILD_PATH="$PROJECT_ROOT/.build"
CACHE_PATH="$PROJECT_ROOT/.swiftpm-cache"
APP_PATH="$PROJECT_ROOT/dist/一日.app"
CONTENTS_PATH="$APP_PATH/Contents"

developer_candidates=()
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  developer_candidates+=("$DEVELOPER_DIR")
fi

active_developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -n "$active_developer_dir" ]]; then
  developer_candidates+=("$active_developer_dir")
fi

for xcode_app in /Applications/Xcode*.app(N); do
  developer_candidates+=("$xcode_app/Contents/Developer")
done

SELECTED_DEVELOPER_DIR=""
SDK_PATH=""
SWIFT_BIN=""

for candidate in "${developer_candidates[@]}"; do
  [[ -d "$candidate" ]] || continue

  candidate_sdk="$(env DEVELOPER_DIR="$candidate" /usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  candidate_swift="$(env DEVELOPER_DIR="$candidate" /usr/bin/xcrun --find swift 2>/dev/null || true)"

  if [[ -f "$candidate_sdk/SDKSettings.plist" && -x "$candidate_swift" ]]; then
    SELECTED_DEVELOPER_DIR="$candidate"
    SDK_PATH="$candidate_sdk"
    SWIFT_BIN="$candidate_swift"
    break
  fi
done

if [[ -z "$SDK_PATH" || -z "$SWIFT_BIN" ]]; then
  cat >&2 <<'EOF'
错误：没有找到可用的 macOS SDK 和 Swift 工具链。

请先安装最新版 Xcode 或 Command Line Tools。安装 Xcode 后可运行：
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -runFirstLaunch

然后重新执行 ./scripts/build-app.sh。
EOF
  exit 1
fi

echo "Using developer tools: $SELECTED_DEVELOPER_DIR"
echo "Using macOS SDK: $SDK_PATH"

env \
  DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" \
  SDKROOT="$SDK_PATH" \
  CLANG_MODULE_CACHE_PATH="$BUILD_PATH/module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_PATH/module-cache" \
  "$SWIFT_BIN" build \
    -c release \
    -Xswiftc -warnings-as-errors \
    --scratch-path "$BUILD_PATH" \
    --cache-path "$CACHE_PATH"

BIN_PATH="$(env \
  DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" \
  SDKROOT="$SDK_PATH" \
  CLANG_MODULE_CACHE_PATH="$BUILD_PATH/module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_PATH/module-cache" \
  "$SWIFT_BIN" build \
    -c release \
    --scratch-path "$BUILD_PATH" \
    --cache-path "$CACHE_PATH" \
    --show-bin-path)"

mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
cp "$BIN_PATH/YiRi" "$CONTENTS_PATH/MacOS/YiRi"
cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS_PATH/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$CONTENTS_PATH/Resources/AppIcon.icns"
chmod +x "$CONTENTS_PATH/MacOS/YiRi"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH"
fi

echo "$APP_PATH"
