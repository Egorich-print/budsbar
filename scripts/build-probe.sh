#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Package the diagnostic with its own Bluetooth permission identity.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SDK="${BUDSBAR_SDK:-$(xcrun --sdk macosx27.2 --show-sdk-path)}"
APP="$ROOT/build/BudsProbe.app"
swift build --sdk "$SDK" --product BudsProbe "$@"
BIN_DIR="$(swift build --sdk "$SDK" --show-bin-path "$@")"

mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/BudsProbe" "$APP/Contents/MacOS/BudsProbe"
cp "$ROOT/Resources/BudsProbe-Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP using SDK $SDK"
