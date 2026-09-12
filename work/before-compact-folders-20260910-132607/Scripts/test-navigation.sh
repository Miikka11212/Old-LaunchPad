#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/oldlaunchpad-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$check_dir/module-cache" \
  "$project_dir/Sources/OldLaunchpad/Navigation.swift" \
  "$project_dir/Sources/OldLaunchpad/LauncherLayout.swift" \
  "$project_dir/Tests/OldLaunchpadTests/LauncherLayoutTests.swift" \
  "$project_dir/Sources/OldLaunchpad/AppVisibility.swift" \
  "$project_dir/Tests/OldLaunchpadTests/AppVisibilityTests.swift" \
  "$project_dir/Tests/OldLaunchpadTests/NavigationTests.swift" \
  -o "$check_dir/navigation-checks"
"$check_dir/navigation-checks"
