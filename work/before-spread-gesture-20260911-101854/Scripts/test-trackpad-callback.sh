#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/oldlaunchpad-callback.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
cat > "$check_dir/module.modulemap" <<EOF
module TrackpadBridge {
  header "$project_dir/Sources/TrackpadBridge/include/TrackpadBridge.h"
  export *
}
EOF
clang -I "$project_dir/Sources/TrackpadBridge/include" -c \
  "$project_dir/Sources/TrackpadBridge/TrackpadBridge.c" -o "$check_dir/bridge.o"
swiftc -swift-version 6 -I "$check_dir" -module-cache-path "$check_dir/module-cache" \
  "$project_dir/Sources/OldLaunchpad/PinchRecognizer.swift" \
  "$project_dir/Sources/OldLaunchpad/TrackpadPinchMonitor.swift" \
  "$project_dir/Tests/OldLaunchpadTests/TrackpadCallbackTests.swift" \
  "$check_dir/bridge.o" -o "$check_dir/callback-checks"
"$check_dir/callback-checks"
