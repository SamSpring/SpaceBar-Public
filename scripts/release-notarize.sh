#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/release-common.sh"
[[ $# == 2 ]] || {
    echo 'Usage: NOTARY_PROFILE=existing-profile bash scripts/release-notarize.sh INPUT.app-or-signed.zip release-output/NEW-NAME' >&2; exit 2;
}
[[ -n "${NOTARY_PROFILE:-}" ]] || { echo 'An existing notarytool Keychain profile is required.' >&2; exit 2; }
input="$(python3 - "$1" <<'PY'
import pathlib,sys
print(pathlib.Path(sys.argv[1]).resolve(strict=True))
PY
)"
stage="$(mktemp -d /tmp/spacebar-notarize.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
app="$stage/SpaceBar.app"
# Extract the durable signed ZIP outside cloud storage. App-directory input is
# retained for already-local callers, with the same strict signature gate.
if [[ -f "$input" && "$input" == *.zip ]]; then
    python3 - "$input" <<'PY'
import posixpath,stat,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for entry in z.infolist():
        name=entry.filename
        parts=name.split('/')
        assert not name.startswith('/') and '\\' not in name and '..' not in parts, 'Unsafe archive path.'
        assert parts[0] in ('SpaceBar.app','__MACOSX'), 'Expected only SpaceBar.app and ZIP metadata.'
        if stat.S_ISLNK(entry.external_attr >> 16):
            target=z.read(entry).decode('utf-8')
            resolved=posixpath.normpath(posixpath.join(posixpath.dirname(name),target))
            assert not target.startswith('/') and '\\' not in target, 'Unsafe archive symlink.'
            assert resolved.startswith(parts[0]+'/'), 'Archive symlink leaves its app.'
PY
    /usr/bin/ditto -x -k --noextattr --norsrc "$input" "$stage"
else
    [[ -d "$input" && "$input" == *.app ]] || { echo 'Expected a signed ZIP or app directory.' >&2; exit 2; }
    /usr/bin/ditto --noextattr --norsrc "$input" "$app"
fi
# Check before creating output or submitting anything to Apple.
check_developer_id "$app"
cd "$release_root"
output="$(new_output "$2")"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$output/notarization-upload.zip"
xcrun notarytool submit "$output/notarization-upload.zip" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json > "$output/notarization-result.json"
python3 - "$output/notarization-result.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('status') != 'Accepted':
    sys.exit('Notarization was not Accepted. Retain the result and fetch the submission log; do not release.')
PY
submission_id="$(python3 - "$output/notarization-result.json" <<'PY'
import json,sys,uuid
print(uuid.UUID(json.load(open(sys.argv[1]))['id']))
PY
)"
xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" \
    "$output/notarization-log.json"
python3 - "$output/notarization-log.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r.get('status')=='Accepted', 'The notarization log must confirm acceptance.'
issues=r.get('issues') or []
assert not any(i.get('severity')=='error' for i in issues), 'Resolve notarization errors before release.'
if issues:
    print('Notarization has warnings. Review notarization-log.json before release.')
PY
xcrun stapler staple "$app" > "$output/staple.log" 2>&1
xcrun stapler validate "$app" >> "$output/staple.log" 2>&1
check_developer_id "$app"
/usr/bin/syspolicy_check distribution "$app" > "$output/distribution-check.log" 2>&1
/usr/sbin/spctl --assess --type execute --verbose=4 "$app" > "$output/gatekeeper-check.log" 2>&1
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="$output/SpaceBar-$version-arm64.zip"
# Repackage AFTER stapling: ZIP files themselves cannot carry a stapled ticket.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
# Retain an app copy as private evidence; future checks extract the final ZIP.
/usr/bin/ditto "$app" "$output/SpaceBar.app"
(cd "$output" && /usr/bin/shasum -a 256 "$(basename "$archive")" > SHA256SUMS.txt)
python3 - "$output" "$version" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1])
r={'version':sys.argv[2],'architecture':'arm64','notarized':True,'stapled':True,
   'publicInstallationVerified':False,'archive':f'SpaceBar-{sys.argv[2]}-arm64.zip'}
(p/'release-metadata.json').write_text(json.dumps(r,indent=2)+'\n')
PY
echo "Notarized and stapled candidate: $archive"
echo 'Clean quarantined-download installation still requires a separate test before publication.'
