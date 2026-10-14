#!/usr/bin/env python3
"""Configure only the staged bundle. Development builds have no update endpoint."""
import argparse
import base64
import json
import plistlib
from pathlib import Path
from urllib.parse import urlsplit

parser = argparse.ArgumentParser()
parser.add_argument('plist', type=Path)
parser.add_argument('channel', choices=['development', 'public', 'test'])
parser.add_argument('--config', type=Path)
args = parser.parse_args()
info = plistlib.loads(args.plist.read_bytes())
for key in ['SUFeedURL', 'SUPublicEDKey', 'SpaceBarLocalUpdaterTest']:
    info.pop(key, None)
info['SpaceBarUpdateChannel'] = args.channel
for key in ['SUEnableAutomaticChecks', 'SUAutomaticallyUpdate', 'SUAllowsAutomaticUpdates', 'SUEnableSystemProfiling']:
    info[key] = False
info['SUVerifyUpdateBeforeExtraction'] = True
if args.channel != 'development':
    if args.config is None:
        parser.error('An update configuration with feedUrl and publicKey is required.')
    config = json.loads(args.config.read_text())
    feed, public_key = config.get('feedUrl'), config.get('publicKey')
    if not isinstance(feed, str) or not isinstance(public_key, str):
        parser.error('Set the update feed URL and Ed25519 public key before building.')
    url = urlsplit(feed)
    local = url.hostname in ['localhost', '127.0.0.1', '::1']
    try:
        valid_key = len(base64.b64decode(public_key, validate=True)) == 32
    except ValueError:
        valid_key = False
    valid_url = (url.scheme == 'https' or (args.channel == 'test' and url.scheme == 'http' and url.hostname == '127.0.0.1'))
    if not (valid_url and url.hostname and not url.username and not url.password and not url.fragment
            and url.path.endswith('.xml') and valid_key and (not local or args.channel == 'test')):
        parser.error('Use an HTTPS .xml feed and a base64 32-byte Ed25519 public key.')
    if args.channel == 'test':
        if not info['CFBundleIdentifier'].endswith('.UpdaterTests'):
            parser.error('Updater tests require a separate .UpdaterTests bundle identifier.')
        info['SpaceBarLocalUpdaterTest'] = True
        info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
    info['SUFeedURL'], info['SUPublicEDKey'] = feed, public_key
args.plist.write_bytes(plistlib.dumps(info, sort_keys=False))
