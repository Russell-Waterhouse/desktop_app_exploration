#!/usr/bin/env bash
# Build zig-dvui on Linux.
# This script contains no Ubuntu-specific commands: it only runs Zig,
# which is why it is build_linux.sh, not build_ubuntu.sh.
# Install Zig first on Ubuntu with ./install_ubuntu.sh
# (or the equivalent download for your distribution).
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

zig build

echo "Built: ./zig-out/bin/zig-dvui"
echo "Run: ./zig-out/bin/zig-dvui"
