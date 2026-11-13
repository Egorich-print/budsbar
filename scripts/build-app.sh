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
CONFIG="${CONFIG:-release}"

# Build with the macOS 27.2 SDK from the selected toolchain.
SDK="${BUDSBAR_SDK:-$(xcrun --sdk macosx27.2 --show-sdk-path)}"
SDK_ARGS=(--sdk "$SDK")
echo "==> SDK: $SDK"

# The `${arr[@]+...}` form keeps `set -u` happy when the array is empty —
# plain "${arr[@]}" is an unbound-variable error in bash 3.2.
echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} --product "$APP_NAME" "$@"

BIN="$(swift build -c "$CONFIG" ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} --show-bin-path "$@")/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
	echo "error: binary not found at $BIN" >&2
	exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$(dirname "$BIN")/BudsBar_BudsBar.bundle" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Stamp the version of the release the bundle was built from.
#
# The plist carries a fallback for builds made outside a checkout; a build
# from a tagged commit reports that tag, so the app in the wild says which
# version it is.
VERSION="$(git describe --tags --abbrev=0 2>/dev/null || true)"
VERSION="${VERSION#v}"
if [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
		"$APP/Contents/Info.plist" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" \
		"$APP/Contents/Info.plist" >/dev/null 2>&1 || true
	echo "==> Version $VERSION"
fi

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
