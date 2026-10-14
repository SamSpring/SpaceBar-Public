#!/bin/bash
set -euo pipefail
[[ $# == 4 ]] || { echo 'Usage: embed-sparkle.sh APP FRAMEWORK local|developer-id IDENTITY' >&2; exit 2; }
app="$1"; source_framework="$2"; mode="$3"; identity="$4"
framework="$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/Frameworks"
/usr/bin/ditto --noextattr --norsrc "$source_framework" "$framework"
# Sign known nested code from the inside out. Preserve Sparkle helper entitlements.
for relative in 'Versions/B/XPCServices/Downloader.xpc' 'Versions/B/XPCServices/Installer.xpc' \
                'Versions/B/Autoupdate' 'Versions/B/Updater.app' ''; do
    target="$framework${relative:+/$relative}"
    [[ -e "$target" ]] || { echo 'Unexpected Sparkle framework structure.' >&2; exit 1; }
    if [[ "$mode" == developer-id ]]; then
        /usr/bin/codesign --force --sign "$identity" --options runtime --timestamp --preserve-metadata=entitlements "$target"
    else
        /usr/bin/codesign --force --sign - --options runtime --timestamp=none --preserve-metadata=entitlements "$target"
    fi
done
/usr/bin/codesign --verify --deep --strict "$framework"
