#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run tests with the macOS 27.2 SDK from the selected Xcode toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SDK="${BUDSBAR_SDK:-$(xcrun --sdk macosx27.2 --show-sdk-path)}"
exec swift test --sdk "$SDK" "$@"
