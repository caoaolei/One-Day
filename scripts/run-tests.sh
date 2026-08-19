#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
BUILD_PATH="$PROJECT_ROOT/.build/app-store-checks"

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
SWIFTC_BIN=""
for candidate in "${developer_candidates[@]}"; do
  [[ -d "$candidate" ]] || continue
  candidate_sdk="$(env DEVELOPER_DIR="$candidate" /usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  candidate_swiftc="$(env DEVELOPER_DIR="$candidate" /usr/bin/xcrun --find swiftc 2>/dev/null || true)"
  if [[ -f "$candidate_sdk/SDKSettings.plist" && -x "$candidate_swiftc" ]]; then
    SELECTED_DEVELOPER_DIR="$candidate"
    SDK_PATH="$candidate_sdk"
    SWIFTC_BIN="$candidate_swiftc"
    break
  fi
done

if [[ -z "$SDK_PATH" || -z "$SWIFTC_BIN" ]]; then
  echo "错误：没有找到可用的 macOS SDK 和 Swift 编译器。" >&2
  exit 1
fi

mkdir -p "$BUILD_PATH/module-cache"

env \
  DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" \
  SDKROOT="$SDK_PATH" \
  CLANG_MODULE_CACHE_PATH="$BUILD_PATH/module-cache" \
  SWIFT_MODULE_CACHE_PATH="$BUILD_PATH/module-cache" \
  "$SWIFTC_BIN" \
    -parse-as-library \
    -swift-version 6 \
    -warnings-as-errors \
    "$PROJECT_ROOT/Sources/YiRiApp/Models.swift" \
    "$PROJECT_ROOT/Sources/YiRiApp/HistoryInsights.swift" \
    "$PROJECT_ROOT/Tests/AppStoreChecks/NotificationManagerStub.swift" \
    "$PROJECT_ROOT/Sources/YiRiApp/AppStore.swift" \
    "$PROJECT_ROOT/Tests/AppStoreChecks/main.swift" \
    -o "$BUILD_PATH/AppStoreChecks"

"$BUILD_PATH/AppStoreChecks"
