#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/oldlaunchpad-pinch.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$check_dir/module-cache" \
  "$project_dir/Sources/OldLaunchpad/PinchRecognizer.swift" \
  "$project_dir/Tests/OldLaunchpadTests/PinchRecognizerTests.swift" \
  -o "$check_dir/pinch-checks"
"$check_dir/pinch-checks"
