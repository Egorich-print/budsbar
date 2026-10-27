#!/usr/bin/env bash
# BudsBar — render the control panel to PNG
# SPDX-License-Identifier: MIT
#
# The renderer is packaged as a small .app bundle so the system loads the
# SF Symbols font; a bare command-line binary cannot resolve symbols.
#
#   scripts/render-panel.sh <output.png> [connected|cancelling|offline]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$ROOT/docs/images/panel-connected.png}"
VARIANT="${2:-connected}"
WORK="$ROOT/build/PanelShot"
APP="$WORK/PanelShot.app"

# See scripts/build-app.sh for why the SDK is chosen this way.
DEFAULT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -n "${BUDSBAR_SDK:-}" ]]; then
	SDK="$BUDSBAR_SDK"
elif [[ -d "$DEFAULT_SDK" ]]; then
	SDK="$DEFAULT_SDK"
else
	SDK=""
fi
SDK_ARGS=()
if [[ -n "$SDK" ]]; then
	SDK_ARGS=(--sdk "$SDK")
fi

echo "==> Building renderer"
swift build -c release ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} --product BudsPanelShot

BIN="$(swift build -c release ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} --show-bin-path)/BudsPanelShot"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/PanelShot"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>PanelShot</string>
	<key>CFBundleIdentifier</key><string>dev.budsbar.PanelShot</string>
	<key>CFBundleName</key><string>PanelShot</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || codesign --force --sign - "$APP"

mkdir -p "$(dirname "$OUT")"
echo "==> Rendering $VARIANT"
"$APP/Contents/MacOS/PanelShot" "$OUT" "$VARIANT"
