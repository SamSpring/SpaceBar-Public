#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/release-common.sh"
[[ $# == 2 ]] || { echo 'Usage: release-appcast.sh NOTARIZED_OUTPUT release-output/NEW-FEED' >&2; exit 2; }
: "${SPARKLE_TOOLS:?Set SPARKLE_TOOLS to the official Sparkle 2.10.0 bin directory}"
: "${SPARKLE_KEY_ACCOUNT:?Set SPARKLE_KEY_ACCOUNT to the EXISTING signing-key Keychain account}"
input="$(cd "$1" && pwd)"
cd "$release_root"
(cd "$input" && /usr/bin/shasum -a 256 -c SHA256SUMS.txt)
stage="$(mktemp -d /tmp/spacebar-feed-check.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
archive_name="$(python3 - "$input/release-metadata.json" <<'PY'
import json,re,sys
name=json.load(open(sys.argv[1]))['archive']
assert re.fullmatch(r'SpaceBar-\d+\.\d+\.\d+-arm64\.zip',name)
print(name)
PY
)"
/usr/bin/ditto -x -k "$input/$archive_name" "$stage"
app="$stage/SpaceBar.app"
check_developer_id "$app"
xcrun stapler validate "$app"
# No key is generated/imported by this workflow. -p reads the existing PUBLIC key.
public_key="$("$SPARKLE_TOOLS/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p)"
python3 - "$input" "$public_key" "$app" <<'PY'
import json,pathlib,plistlib,re,sys,urllib.parse
p=pathlib.Path(sys.argv[1]); meta=json.loads((p/'release-metadata.json').read_text())
config=json.load(open('release/update-config.json')); site=json.load(open('site/release.json'))
assert meta['notarized'] is True and meta['stapled'] is True
assert config['publicKey'] == sys.argv[2].strip(), 'Signing key does not match embedded public key.'
info=plistlib.loads((pathlib.Path(sys.argv[3])/'Contents/Info.plist').read_bytes())
assert info.get('SUPublicEDKey') == config['publicKey'], 'Archived app has a different update public key.'
assert info.get('SUFeedURL') == config['feedUrl'], 'Archived app has a different feed URL.'
url=urllib.parse.urlsplit(config['feedUrl'] or '')
assert url.scheme == 'https' and url.hostname and not url.username and not url.password
assert re.fullmatch(r'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', site['repositoryUrl'] or ''), 'Set the approved public repository URL first.'
assert meta['version'] == info['CFBundleShortVersionString'] and re.fullmatch(r'\d+\.\d+\.\d+',meta['version'])
PY
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
repo="$(python3 -c 'import json; print(json.load(open("site/release.json"))["repositoryUrl"])')"
output="$(new_output "$2")"
archive="SpaceBar-$version-arm64.zip"
if [[ -n "${PREVIOUS_FEED_STAGE:-}" ]]; then
    python3 - "$PREVIOUS_FEED_STAGE" "$output" <<'PY'
import pathlib,re,shutil,sys
previous=pathlib.Path(sys.argv[1]).resolve(); output=pathlib.Path(sys.argv[2])
assert (previous/'appcast.xml').is_file(), 'Previous staging must contain the reviewed feed.'
for p in previous.iterdir():
    if p.name=='appcast.xml' or re.fullmatch(r'SpaceBar-\d+\.\d+\.\d+-arm64\.(zip|md)',p.name):
        assert p.is_file() and not p.is_symlink(), 'Previous artifacts must be regular files.'
        shutil.copyfile(p,output/p.name)
PY
fi
[[ ! -e "$output/$archive" ]] || { echo 'A released archive name cannot be overwritten.' >&2; exit 1; }
cp "$input/$archive" "$output/$archive"
notes="${RELEASE_NOTES_PATH:-RELEASE_NOTES.md}"
if [[ ! -f "$notes" && -f public-docs/RELEASE_NOTES.md ]]; then notes='public-docs/RELEASE_NOTES.md'; fi
cp "$notes" "$output/SpaceBar-$version-arm64.md"
"$SPARKLE_TOOLS/generate_appcast" --account "$SPARKLE_KEY_ACCOUNT" --maximum-deltas 0 \
    --download-url-prefix "$repo/releases/download/v$version/" --embed-release-notes "$output"
# generate_appcast reapplies its download prefix to older archives too.
# Restore previously published items in full before completing the NEW item.
if [[ -n "${PREVIOUS_FEED_STAGE:-}" ]]; then
    python3 - "$output/appcast.xml" "$PREVIOUS_FEED_STAGE/appcast.xml" <<'PYHISTORY'
from pathlib import Path
import sys,xml.etree.ElementTree as ET
feed,previous=map(Path,sys.argv[1:])
ns='http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',ns)
key='{'+ns+'}version'
tree=ET.parse(feed);channel=tree.find('channel');assert channel is not None
old_items=ET.parse(previous).findall('./channel/item')
old_by_build={item.findtext(key):item for item in old_items}
assert len(old_by_build)==len(old_items) and None not in old_by_build, 'Invalid previous feed versions.'
for index,item in enumerate(list(channel)):
    if item.tag=='item' and item.findtext(key) in old_by_build:
        channel.remove(item);channel.insert(index,old_by_build.pop(item.findtext(key)))
assert not old_by_build, 'Generator dropped a published feed item.'
ET.indent(tree,space='    ')
tree.write(feed,encoding='utf-8',xml_declaration=True)
PYHISTORY
fi
python3 scripts/complete-appcast.py "$output/appcast.xml" "$app"
python3 scripts/validate-appcast.py "$output/appcast.xml" "$output/$archive" "$app"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
signature="$(python3 - "$output/appcast.xml" "$build" <<'PY'
import sys,xml.etree.ElementTree as ET
ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
item=next(i for i in ET.parse(sys.argv[1]).findall('./channel/item') if i.findtext(ns+'version')==sys.argv[2])
print(item.find('enclosure').attrib[ns+'edSignature'])
PY
)"
"$SPARKLE_TOOLS/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$output/$archive" "$signature"
echo 'Feed prepared privately. Publish only the reviewed appcast.xml and the exact final archive after installation QA.'
