#!/usr/bin/env bash
# BudsBar — build the .app bundle
# SPDX-License-Identifier: MIT
#
# The project is built with Swift Package Manager only; no Xcode project is
# needed. This script assembles the .app bundle and ad-hoc signs it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="BudsBar"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
SDK="${BUDSBAR_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
CONFIG="${CONFIG:-release}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --sdk "$SDK" --product "$APP_NAME"

BIN="$(swift build -c "$CONFIG" --sdk "$SDK" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
	echo "error: binary not found at $BIN" >&2
	exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Icon: generate a simple template so the bundle has a valid app icon slot.
if [[ -f "$ROOT/Resources/BudsBar.icns" ]]; then
	cp "$ROOT/Resources/BudsBar.icns" "$APP/Contents/Resources/BudsBar.icns"
fi

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null \
	|| codesign --force --sign - "$APP"

codesign --verify --deep --strict "$APP" && echo "    signature ok"

echo "==> Built $APP"
du -sh "$APP"
