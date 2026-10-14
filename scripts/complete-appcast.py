#!/usr/bin/env python3
"""Add the explicit architecture constraint after Sparkle signs the archive."""
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

feed, app = map(Path, sys.argv[1:])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
architectures = subprocess.check_output(['/usr/bin/lipo','-archs',str(app/'Contents/MacOS/SpaceBar')],text=True).strip()
assert architectures == 'arm64', 'Only reviewed arm64 release archives are supported.'
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle',namespace)
key='{'+namespace+'}'
tree=ET.parse(feed)
item=next(i for i in tree.findall('./channel/item') if i.findtext(key+'version') == info['CFBundleVersion'])
hardware=item.find(key+'hardwareRequirements')
if hardware is None: hardware=ET.SubElement(item,key+'hardwareRequirements')
hardware.text='arm64'
minimum=item.find(key+'minimumSystemVersion')
assert minimum is not None and minimum.text in ('27.0','27.0.0')
minimum.text='27.0.0'
# Sparkle's archive signature remains unchanged. Feeds are not yet signed here;
# any optional feed signature must be made AFTER this final schema adjustment.
ET.indent(tree,space='    ')
tree.write(feed,encoding='utf-8',xml_declaration=True)
print('Feed explicitly targets macOS 27 and Apple silicon; archive signature retained.')
