#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
cd "$project_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/Silent Light Trackpad.app"

if [[ "$app_dir" != "$project_dir/dist/Silent Light Trackpad.app" ]]; then
    echo "Unexpected app output path: $app_dir" >&2
    exit 1
fi
/bin/rm -rf -- "$app_dir"
/bin/mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources"
/usr/bin/ditto "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/ditto "$bin_dir/SilentLightTrackpad" "$app_dir/Contents/MacOS/SilentLightTrackpad"
/usr/bin/ditto "$bin_dir/OpenMultitouchSupportXCF.framework" "$app_dir/Contents/Frameworks/OpenMultitouchSupportXCF.framework"
/usr/bin/ditto "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
/usr/bin/ditto "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "$project_dir/ThirdPartyLicenses" "$app_dir/Contents/Resources/ThirdPartyLicenses"

rpaths() {
    /usr/bin/otool -l "$app_dir/Contents/MacOS/SilentLightTrackpad" | /usr/bin/awk '
        $1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }
    '
}

if ! rpaths | /usr/bin/grep -Fxq '@executable_path/../Frameworks'; then
    /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$app_dir/Contents/MacOS/SilentLightTrackpad"
fi
while IFS= read -r rpath; do
    case "$rpath" in
        /Library/Developer/*|/Applications/Xcode.app/*)
            /usr/bin/install_name_tool -delete_rpath "$rpath" "$app_dir/Contents/MacOS/SilentLightTrackpad"
            ;;
    esac
done < <(rpaths)
if ! rpaths | /usr/bin/grep -Fxq '@executable_path/../Frameworks'; then
    echo "Required framework RPATH is missing" >&2
    exit 1
fi
/usr/bin/codesign --force --sign - "$app_dir/Contents/Frameworks/OpenMultitouchSupportXCF.framework"
/usr/bin/codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
