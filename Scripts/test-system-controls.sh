#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/oldlaunchpad-controls.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$check_dir/module-cache" \
  "$project_dir/Sources/OldLaunchpad/SystemControlSession.swift" \
  "$project_dir/Tests/OldLaunchpadTests/SystemControlSessionTests.swift" \
  -o "$check_dir/control-checks"
"$check_dir/control-checks"
