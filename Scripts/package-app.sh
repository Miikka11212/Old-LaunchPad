#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${1:-"$project_dir/outputs"}
stage_dir=$(mktemp -d /private/tmp/oldlaunchpad-package.XXXXXX)
trap 'rm -rf "$stage_dir"' EXIT

if [ -n "${OLDLAUNCHPAD_BINARY:-}" ]; then
    binary=$OLDLAUNCHPAD_BINARY
else
    swift build --build-system native --scratch-path "$stage_dir/build" \
        --package-path "$project_dir" -c release
    binary="$stage_dir/build/release/OldLaunchpad"
fi

app="$stage_dir/OldLaunchpad.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$binary" "$app/Contents/MacOS/OldLaunchpad"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/ThirdParty/OpenMultitouchSupport-LICENSE.txt" "$app/Contents/Resources/"
cp "$project_dir/README.md" "$app/Contents/Resources/Read Me.md"
swift "$project_dir/Scripts/render-app-icon.swift" "$stage_dir/AppIcon.iconset"
iconutil -c icns "$stage_dir/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"

mkdir -p "$output_dir"
# Archive the clean staged bundle before desktop/cloud services can add metadata.
ditto -c -k --sequesterRsrc --keepParent "$app" "$output_dir/OldLaunchpad.zip"
ditto "$app" "$output_dir/OldLaunchpad.app"
printf 'Packaged app: %s\nArchive: %s\n' "$output_dir/OldLaunchpad.app" "$output_dir/OldLaunchpad.zip"
