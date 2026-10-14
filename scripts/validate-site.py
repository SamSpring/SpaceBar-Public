#!/usr/bin/env python3
"""Check the static site; --release also requires validated download metadata."""
import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--release', action='store_true')
args = parser.parse_args()
config = json.loads((root/'site/release.json').read_text())
assert config['supportUrl'] == 'https://ko-fi.com/samspring', 'Unexpected donation account'
assert config['architecture'] == 'arm64' and config['minimumMacOS'] == '27.0'
repo = config['repositoryUrl']
if repo is not None:
    assert re.fullmatch(r'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo), 'Invalid repository URL'
if args.release or config['downloadUrl'] is not None:
    assert repo and config['notarized'] is True and config['cleanInstallVerified'] is True, 'Download is not release-validated'
    assert re.fullmatch(r'\d+\.\d+\.\d+',config['version']), 'Invalid version'
    assert re.fullmatch(r'[a-f0-9]{64}', config['sha256'] or ''), 'Missing checksum'
    assert config['downloadUrl'] == f"{repo}/releases/download/v{config['version']}/SpaceBar-{config['version']}-arm64.zip", 'Unexpected release asset URL'

class LocalFiles(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key,value in attrs:
            if key in ('href','src','poster') and value and not value.startswith('#'):
                url = urlsplit(value)
                if url.scheme:
                    assert url.scheme == 'https', 'Only HTTPS external links are allowed'
                elif value != './':
                    assert (root/'site'/url.path).is_file(), f'Missing site asset: {value}'
LocalFiles().feed((root/'site/index.html').read_text())
print('Site assets and configuration pass'+(' the release gate.' if args.release else ' preview checks.'))
