#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
TEST_BIN="$(mktemp -d)/steam-guard-test"
clang \
  -fobjc-arc \
  -Wall -Wextra \
  -DSecItemCopyMatching=TestSecItemCopyMatching \
  -DSecItemUpdate=TestSecItemUpdate \
  -DSecItemAdd=TestSecItemAdd \
  -DSecItemDelete=TestSecItemDelete \
  -framework Foundation \
  -framework Security \
  -I "$ROOT_DIR/Sources" \
  "$ROOT_DIR/Sources/SteamGuard.m" \
  "$ROOT_DIR/Sources/SteamAccounts.m" \
  "$ROOT_DIR/Sources/AccountsKeychain.m" \
  "$ROOT_DIR/Sources/MaFileImport.m" \
  "$ROOT_DIR/Tests/SteamGuardVector.m" \
  -o "$TEST_BIN"
"$TEST_BIN"
