#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
configuration="${BUILD_CONFIGURATION:-release}"
bundle_name="${BUILD_APP_NAME:-SpaceBar}"
bundle_id="${BUILD_BUNDLE_ID:-local.samuelaviv.MenuBarSpacers}"
signing_identity="${SIGNING_IDENTITY:-}"
scratch_dir="${BUILD_SCRATCH_PATH:-${TMPDIR:-/tmp}/spacebar-build}"
update_channel="${SPACEBAR_UPDATE_CHANNEL:-development}"
executable="${BUILD_EXECUTABLE:-SpaceBar}"
output_dir="${BUILD_OUTPUT_DIR:-$project_dir/dist}"
case "$update_channel" in
    development) [[ "$executable" == SpaceBar ]] || { echo 'Harness requires the test channel.' >&2; exit 2; } ;;
    public)
        [[ "$signing_identity" == 'Developer ID Application: '* && "$bundle_id" == local.samuelaviv.MenuBarSpacers && "$executable" == SpaceBar ]] || {
            echo 'Public update builds require Developer ID signing and the existing SpaceBar identity.' >&2; exit 2;
        } ;;
    test)
        [[ "$bundle_id" == *.UpdaterTests && "$executable" == SpaceBarUpdateHarness ]] || {
            echo 'Local updater tests require the isolated harness and .UpdaterTests identity.' >&2; exit 2;
        } ;;
    *) echo 'Unknown SPACEBAR_UPDATE_CHANNEL.' >&2; exit 2 ;;
esac
export SPACEBAR_UPDATE_CHANNEL="$update_channel"

swift scripts/generate-icon.swift "$project_dir"
swift build --product "$executable" --scratch-path "$scratch_dir" -c "$configuration"
binary_dir="$(swift build --scratch-path "$scratch_dir" -c "$configuration" --show-bin-path)"
app_path="$output_dir/$bundle_name.app"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/spacebar-bundle.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
staged_app="$stage_dir/$bundle_name.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
/usr/bin/ditto --noextattr --norsrc "$binary_dir/$executable" "$staged_app/Contents/MacOS/SpaceBar"
/usr/bin/ditto --noextattr --norsrc Resources/Info.plist "$staged_app/Contents/Info.plist"
/usr/bin/ditto --noextattr --norsrc Resources/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $bundle_name" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $bundle_name" "$staged_app/Contents/Info.plist"
if [[ "$update_channel" == development ]]; then
    python3 scripts/configure-updates.py "$staged_app/Contents/Info.plist" development
else
    python3 scripts/configure-updates.py "$staged_app/Contents/Info.plist" "$update_channel" --config "${BUILD_UPDATE_CONFIG:?Set BUILD_UPDATE_CONFIG}"
    framework="$scratch_dir/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    [[ -d "$framework" ]] || { echo 'Pinned Sparkle framework is missing.' >&2; exit 1; }
    mode=local
    [[ "$update_channel" != public ]] || mode=developer-id
    bash scripts/embed-sparkle.sh "$staged_app" "$framework" "$mode" "$signing_identity"
    /usr/bin/ditto --noextattr --norsrc Resources/Sparkle-LICENSE "$staged_app/Contents/Resources/Sparkle-LICENSE"
fi
if [[ "$update_channel" == test ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_TEST_VERSION:-1}" "$staged_app/Contents/Info.plist"
    cat > "$stage_dir/test-entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>
PLIST
    codesign --force --sign - --options runtime --entitlements "$stage_dir/test-entitlements.plist" "$staged_app"
elif [[ -n "$signing_identity" ]]; then
    codesign --force --sign "$signing_identity" --options runtime --timestamp "$staged_app"
elif [[ "$bundle_id" == "local.samuelaviv.MenuBarSpacers" ]]; then
    python3 scripts/local-signing.py --prepare
    python3 scripts/local-signing.py --sign "$staged_app"
else
    codesign --force --sign - --options runtime "$staged_app"
fi
codesign --verify --deep --strict "$staged_app"
mkdir -p "$output_dir"
[[ ! -L "$app_path" ]] || { echo 'Refusing to replace an app symlink.' >&2; exit 1; }
destination_stage="$(mktemp -d "$output_dir/.spacebar-stage.XXXXXX")"
/usr/bin/ditto --noextattr --norsrc "$staged_app" "$destination_stage/$bundle_name.app"
codesign --verify --deep --strict "$destination_stage/$bundle_name.app"
if [[ -e "$app_path" ]]; then mv "$app_path" "$stage_dir/previous.app"; fi
mv "$destination_stage/$bundle_name.app" "$app_path"
rmdir "$destination_stage"
echo "$app_path"
