#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
APP_NAME="Steam Guard Lite"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

mkdir -p "$MACOS_DIR"

clang \
  -fobjc-arc \
  -Wall -Wextra \
  -O \
  -mmacosx-version-min=13.0 \
  -framework Cocoa \
  -framework Security \
  -framework WebKit \
  -I "$ROOT_DIR/Sources" \
  "$ROOT_DIR/Sources/SteamGuard.m" \
  "$ROOT_DIR/Sources/SteamAccounts.m" \
  "$ROOT_DIR/Sources/AccountsKeychain.m" \
  "$ROOT_DIR/Sources/MaFileImport.m" \
  "$ROOT_DIR/Sources/SteamConfirmations.m" \
  "$ROOT_DIR/Sources/ConfirmationsWindow.m" \
  "$ROOT_DIR/Sources/main.m" \
  -o "$MACOS_DIR/SteamGuardLite"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"
