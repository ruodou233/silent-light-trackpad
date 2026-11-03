#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
cd "$project_dir"

swift build -j 2 -c release
bin_dir="$(swift build -j 2 -c release --show-bin-path)"
app_dir="$project_dir/dist/Silent Light Trackpad.app"

if [[ "$app_dir" != "$project_dir/dist/Silent Light Trackpad.app" ]]; then
    echo "Unexpected app output path: $app_dir" >&2
    exit 1
fi
/bin/rm -rf -- "$app_dir"
/bin/mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
/usr/bin/ditto "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/ditto "$bin_dir/SilentLightTrackpad" "$app_dir/Contents/MacOS/SilentLightTrackpad"
/usr/bin/ditto "$project_dir/assets/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"

/usr/bin/codesign --force --sign - "$app_dir"

echo "$app_dir"
