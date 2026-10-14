#!/bin/bash
# Safe public-source default: isolated development preview, no signing keys.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
output="${1:-release-output/development-$(date +%Y%m%d-%H%M%S)-$$}"
exec bash scripts/release-build.sh local "$output"
