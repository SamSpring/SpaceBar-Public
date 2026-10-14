#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/release-common.sh"
[[ $# == 2 && ( "$1" == local || "$1" == developer-id ) ]] || {
    echo 'Usage: bash scripts/release-build.sh local|developer-id release-output/NEW-NAME' >&2; exit 2;
}
mode="$1"
cd "$release_root"
if [[ "$mode" == developer-id ]]; then
    [[ "${SIGNING_IDENTITY:-}" == 'Developer ID Application: '* ]] || {
        echo 'An existing Developer ID Application certificate is required.' >&2; exit 2;
    }
    config_check="$(mktemp /tmp/spacebar-public-config.XXXXXX)"
    cp Resources/Info.plist "$config_check"
    if ! python3 scripts/configure-updates.py "$config_check" public --config release/update-config.json; then
        rm -f "$config_check"; exit 2
    fi
    rm -f "$config_check"
fi
output="$(new_output "$2")"
stage="$(mktemp -d /tmp/spacebar-release-build.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
builder='scripts/build-app.sh'
[[ -f "$builder" ]] || builder='scripts/build.sh'
name='SpaceBar'
if [[ "$mode" == local ]]; then
    name='SpaceBar Preview'
    SPACEBAR_UPDATE_CHANNEL=development BUILD_APP_NAME="$name" \
      BUILD_BUNDLE_ID=local.samuelaviv.MenuBarSpacers.UITests SIGNING_IDENTITY=- \
      BUILD_SCRATCH_PATH="$stage/scratch" BUILD_OUTPUT_DIR="$stage/output" \
      bash "$builder" > "$output/build.log" 2>&1
else
    SPACEBAR_UPDATE_CHANNEL=public BUILD_UPDATE_CONFIG="$release_root/release/update-config.json" \
      SIGNING_IDENTITY="$SIGNING_IDENTITY" BUILD_SCRATCH_PATH="$stage/scratch" \
      BUILD_OUTPUT_DIR="$stage/output" bash "$builder" > "$output/build.log" 2>&1
fi
app="$stage/output/$name.app"
cp LICENSE NOTICE "$app/Contents/Resources/"
if [[ "$mode" == local ]]; then
    /usr/bin/codesign --force --sign - --options runtime --timestamp=none "$app"
else
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$app"
    check_developer_id "$app"
fi
/usr/bin/codesign --verify --deep --strict "$app"
python3 - "$app" "$mode" "$output" <<'PY'
import json,pathlib,plistlib,subprocess,sys
app,mode,out=pathlib.Path(sys.argv[1]),sys.argv[2],pathlib.Path(sys.argv[3])
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
arch=subprocess.check_output(['/usr/bin/lipo','-archs',str(app/'Contents/MacOS/SpaceBar')],text=True).strip()
assert arch=='arm64' and info['LSMinimumSystemVersion']=='27.0'
expected='development' if mode=='local' else 'public'
assert info['SpaceBarUpdateChannel']==expected
if mode=='local':
    assert 'SUFeedURL' not in info and 'SUPublicEDKey' not in info
    assert not (app/'Contents/Frameworks/Sparkle.framework').exists()
r={'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],
   'architecture':arch,'minimumMacOS':'27.0','mode':mode,'updateChannel':expected,
   'notarized':False,'publicInstallationVerified':False}
if mode=='local':
    archive=out/f"SpaceBar-{r['version']}-arm64-LOCAL-ONLY.zip"
    (out/'LOCAL-ONLY.txt').write_text('Isolated development preview. No public updater. Not notarized. Do not publish as a public download.\n')
else:
    archive=out/f"SpaceBar-{r['version']}-arm64-SIGNED-UNNOTARIZED.zip"
    r['signedArchive']=archive.name
subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(archive)],check=True)
(out/'build-metadata.json').write_text(json.dumps(r,indent=2)+'\n')
PY
if [[ "$mode" == developer-id ]]; then
    # The durable handoff is a ZIP: cloud sync can strip framework symlinks
    # and directory contents from an unpacked app after its initial validation.
    signed_archive="$(python3 - "$output/build-metadata.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1])
print(p.parent/json.loads(p.read_text())['signedArchive'])
PY
)"
    /usr/bin/ditto -x -k --noextattr --norsrc "$signed_archive" "$stage/round-trip"
    check_developer_id "$stage/round-trip/SpaceBar.app"
else
    /usr/bin/ditto --noextattr --norsrc "$app" "$output/$name.app"
fi
echo "Prepared $mode candidate in $output. No app was launched or installed."
