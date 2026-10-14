#!/bin/bash
# Shared checks; only new directories under this source tree's release-output.
set -euo pipefail
release_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

new_output() {
    python3 - "$release_root" "$1" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1]).resolve()
target = pathlib.Path(sys.argv[2]).absolute()
allowed = root / 'release-output'
if target.is_symlink() or allowed.is_symlink():
    sys.exit('Output paths must not be symbolic links.')
target = target.resolve()
if allowed.resolve() != allowed or allowed not in target.parents or target.exists():
    sys.exit('Choose a NEW directory inside release-output/. Existing paths are protected.')
target.mkdir(parents=True, exist_ok=False)
print(target)
PY
}

check_developer_id() {
    /usr/bin/codesign --verify --deep --strict "$1"
    local details
    details="$(/usr/bin/codesign -dv --verbose=4 "$1" 2>&1)"
    [[ "$details" == *'Authority=Developer ID Application:'* ]] || {
        echo 'A Developer ID Application signature is required.' >&2; return 1;
    }
    [[ "$details" == *'flags='*'(runtime)'* && "$details" == *'Timestamp='* ]] || {
        echo 'Hardened runtime and a secure timestamp are required.' >&2; return 1;
    }
    [[ "$details" == *'TeamIdentifier='* && "$details" != *'TeamIdentifier=not set'* ]] || {
        echo 'A verified Apple Developer team is required.' >&2; return 1;
    }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" == 'local.samuelaviv.MenuBarSpacers' ]] || {
        echo 'The compatibility bundle identifier must be preserved.' >&2; return 1;
    }
}
