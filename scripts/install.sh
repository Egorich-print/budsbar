#!/usr/bin/env bash
# BudsBar — install the app into /Applications
# SPDX-License-Identifier: MIT

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BudsBar"
APP="$ROOT/build/$APP_NAME.app"
TARGET="/Applications/$APP_NAME.app"

if [[ ! -d "$APP" ]]; then
	echo "error: $APP not found — run scripts/build-app.sh first" >&2
	exit 1
fi

echo "==> Installing to $TARGET"

# Stop a running copy first: replacing the bundle under a live process
# leaves the old binary in memory and the new code never takes effect.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
	echo "    stopping the running copy"
	pkill -x "$APP_NAME" || true
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
		sleep 0.3
	done
	if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
		pkill -9 -x "$APP_NAME" || true
		sleep 0.5
	fi
fi

if [[ -e "$TARGET" ]]; then
	echo "    replacing existing installation"
	rm -rf "$TARGET"
fi
cp -R "$APP" "$TARGET"

# A locally built app carries no quarantine attribute, but strip it if the
# bundle was downloaded, so the first launch is not blocked.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "==> Launching"
open -a "$TARGET"

echo "==> Done. Look for the earbud icon in the menu bar."
