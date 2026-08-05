#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
APP_PATH="$PROJECT_ROOT/dist/一日.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")"
ARCHITECTURE="$(uname -m)"
DMG_PATH="${1:-$PROJECT_ROOT/dist/一日-${VERSION}-${ARCHITECTURE}.dmg}"

"$SCRIPT_DIR/build-app.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "错误：没有找到构建产物 $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_PATH"

mkdir -p "$PROJECT_ROOT/.build"
STAGING_PATH="$(mktemp -d "$PROJECT_ROOT/.build/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_PATH"' EXIT

ditto "$APP_PATH" "$STAGING_PATH/一日.app"
ln -s /Applications "$STAGING_PATH/Applications"

hdiutil create \
  -volname "一日" \
  -srcfolder "$STAGING_PATH" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"
echo "$DMG_PATH"
