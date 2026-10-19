#!/usr/bin/env bash
# Build the iOS app with xtool (no Mac, no Xcode app).
#
#   ios/scripts/build.sh            debug .app, unsigned
#   ios/scripts/build.sh --release  signed release .ipa in ios/xtool/
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/check-shared.sh
swift test --filter AOUHubCoreTests

if [[ "${1:-}" == "--release" ]]; then
  xtool dev build --configuration release --sign --ipa
else
  xtool dev build
fi
echo "Built. Output is under ios/xtool/."
