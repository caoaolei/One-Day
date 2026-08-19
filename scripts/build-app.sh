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
mkdir -p "$BUILD_PATH/module-cache"
TOOLCHAIN_PROBE="$BUILD_PATH/toolchain-probe.swift"
printf 'import SwiftUI\n' > "$TOOLCHAIN_PROBE"
TARGET_TRIPLE="$(uname -m)-apple-macosx13.0"

for candidate in "${developer_candidates[@]}"; do
  [[ -d "$candidate" ]] || continue

  candidate_swift="$(env DEVELOPER_DIR="$candidate" /usr/bin/xcrun --find swift 2>/dev/null || true)"
  candidate_swiftc="$(env DEVELOPER_DIR="$candidate" /usr/bin/xcrun --find swiftc 2>/dev/null || true)"
  [[ -x "$candidate_swift" && -x "$candidate_swiftc" ]] || continue

  sdk_candidates=()
  if [[ -n "${SDKROOT:-}" ]]; then
    sdk_candidates+=("$SDKROOT")
  fi
  default_sdk="$(env DEVELOPER_DIR="$candidate" /usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  if [[ -n "$default_sdk" ]]; then
    sdk_candidates+=("$default_sdk")
  fi
  for installed_sdk in "$candidate"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk(N); do
    sdk_candidates+=("$installed_sdk")
  done
  for installed_sdk in "$candidate"/SDKs/MacOSX*.sdk(N); do
    sdk_candidates+=("$installed_sdk")
  done

  for candidate_sdk in "${sdk_candidates[@]}"; do
    [[ -f "$candidate_sdk/SDKSettings.plist" ]] || continue
    if env \
      DEVELOPER_DIR="$candidate" \
      CLANG_MODULE_CACHE_PATH="$BUILD_PATH/module-cache" \
      SWIFT_MODULE_CACHE_PATH="$BUILD_PATH/module-cache" \
      "$candidate_swiftc" \
        -typecheck \
        -sdk "$candidate_sdk" \
        -target "$TARGET_TRIPLE" \
        "$TOOLCHAIN_PROBE" \
        >/dev/null 2>&1; then
      SELECTED_DEVELOPER_DIR="$candidate"
      SDK_PATH="$candidate_sdk"
      SWIFT_BIN="$candidate_swift"
      break 2
    fi
  done
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
    --disable-sandbox \
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
    --disable-sandbox \
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
