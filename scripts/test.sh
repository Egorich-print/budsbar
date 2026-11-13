#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run tests with Xcode or the standalone Command Line Tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ARGS=()
DEFAULT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -n "${BUDSBAR_SDK:-}" ]]; then
	ARGS+=(--sdk "$BUDSBAR_SDK")
elif [[ -d "$DEFAULT_SDK" ]]; then
	ARGS+=(--sdk "$DEFAULT_SDK")
fi

DEVELOPER_DIR_PATH="$(xcode-select -p)"
if [[ "$DEVELOPER_DIR_PATH" == */CommandLineTools ]]; then
	# The native engine needs explicit paths to the Testing framework and
	# its macros when using the standalone tools.
	FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
	PLUGINS="$DEVELOPER_DIR_PATH/usr/lib/swift/host/plugins/testing"
	ARGS+=(
		--build-system native
		-Xswiftc -F -Xswiftc "$FRAMEWORKS"
		-Xswiftc -plugin-path -Xswiftc "$PLUGINS"
		-Xlinker "-F$FRAMEWORKS"
		-Xlinker -rpath -Xlinker "$FRAMEWORKS"
	)
fi

exec swift test ${ARGS[@]+"${ARGS[@]}"} "$@"
