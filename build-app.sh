#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
cd "$project_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/Silent Light Trackpad.app"

/bin/mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources"
/usr/bin/ditto "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/ditto "$bin_dir/SilentLightTrackpad" "$app_dir/Contents/MacOS/SilentLightTrackpad"
/usr/bin/ditto "$bin_dir/OpenMultitouchSupportXCF.framework" "$app_dir/Contents/Frameworks/OpenMultitouchSupportXCF.framework"
/usr/bin/ditto "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "$project_dir/ThirdPartyLicenses" "$app_dir/Contents/Resources/ThirdPartyLicenses"

/usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$app_dir/Contents/MacOS/SilentLightTrackpad" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$app_dir/Contents/Frameworks/OpenMultitouchSupportXCF.framework"
/usr/bin/codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
