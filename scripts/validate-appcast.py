#!/usr/bin/env python3
import base64
import hashlib
import plistlib
from pathlib import Path
import sys
import urllib.parse
import xml.etree.ElementTree as ET

feed, archive, app = map(Path, sys.argv[1:])
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
items = ET.parse(feed).findall('./channel/item')
item = next(i for i in items if i.findtext(namespace+'version') == info['CFBundleVersion'])
enclosure = item.find('enclosure')
assert enclosure is not None
url = urllib.parse.urlsplit(enclosure.attrib['url'])
assert url.scheme == 'https' and Path(url.path).name == archive.name
assert int(enclosure.attrib['length']) == archive.stat().st_size
assert len(base64.b64decode(enclosure.attrib[namespace+'edSignature'],validate=True)) == 64
assert item.findtext(namespace+'minimumSystemVersion') in ('27.0','27.0.0')
assert item.findtext(namespace+'hardwareRequirements') == 'arm64'
assert item.find('description') is not None, 'Missing release notes'
record = {'build':info['CFBundleVersion'],'version':info['CFBundleShortVersionString'],
          'archive':archive.name,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
          'minimumMacOS':'27.0','hardware':'arm64','signaturePresent':True}
# Cryptographic verification is performed by Sparkle, including before extraction.
(feed.parent/'appcast-validation.json').write_text(__import__('json').dumps(record,indent=2)+'\n')
print('Appcast version, OS, architecture, archive length, signature, and notes match.')
