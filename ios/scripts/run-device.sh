#!/usr/bin/env bash
# Build, sign and install on a USB-connected iPhone, then launch it.
# First run: tap "Trust" on the phone, enable Developer Mode, and trust the
# developer profile in Settings > General > VPN & Device Management.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/check-shared.sh
xtool dev run
