#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
TEST_BIN="$(mktemp -d)/steam-guard-window-test"
clang \
  -fobjc-arc \
  -Wall -Wextra \
  -framework Cocoa \
  -framework WebKit \
  -I "$ROOT_DIR/Sources" \
  "$ROOT_DIR/Sources/SteamGuard.m" \
  "$ROOT_DIR/Sources/SteamAccounts.m" \
  "$ROOT_DIR/Sources/MaFileImport.m" \
  "$ROOT_DIR/Sources/SteamConfirmations.m" \
  "$ROOT_DIR/Sources/ConfirmationsWindow.m" \
  "$ROOT_DIR/Tests/AccountWindow.m" \
  -o "$TEST_BIN"
"$TEST_BIN"
