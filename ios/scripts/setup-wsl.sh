#!/usr/bin/env bash
# One-time setup for building the iOS app on Linux / Windows WSL with xtool.
# Safe to re-run: every step checks before it installs.
#
# Needs (from https://github.com/xtool-org/xtool, Installation-Linux):
#   - Swift 6.x toolchain for Linux   https://swift.org/install/linux
#   - usbmuxd (device connection)     sudo apt-get install usbmuxd libimobiledevice-utils
#   - Xcode.xip downloaded by hand    https://developer.apple.com/download/all/?q=Xcode
#   - WSL only: USB passthrough with usbipd-win, or the iTunes relay from xtool issue #19
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1; }

echo "== Swift"
if ! need swift; then
  echo "Swift is missing. Install the Linux toolchain from https://swift.org/install/linux, then re-run." >&2
  exit 1
fi
swift --version | head -1

echo "== usbmuxd"
if ! need usbmuxd; then
  echo "Installing usbmuxd + libimobiledevice-utils (sudo)..."
  sudo apt-get update && sudo apt-get install -y usbmuxd libimobiledevice-utils
fi

echo "== xtool"
if ! need xtool; then
  arch="$(uname -m)"
  echo "Downloading xtool-${arch}.AppImage from the official GitHub release..."
  curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-${arch}.AppImage" -o /tmp/xtool
  chmod +x /tmp/xtool
  sudo mv /tmp/xtool /usr/local/bin/xtool
fi
xtool --help | head -2

echo "== Apple account + Darwin SDK"
if swift sdk list 2>/dev/null | grep -q darwin; then
  echo "darwin SDK already installed."
else
  echo "Running 'xtool setup': choose a login mode, then give the path to Xcode.xip."
  xtool setup
fi

echo "Done. Next: ios/scripts/build.sh (or ios/scripts/run-device.sh with an iPhone attached)."
