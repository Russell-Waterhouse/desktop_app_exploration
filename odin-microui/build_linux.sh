#!/usr/bin/env bash
# Build odin-microui on Linux.
# This script contains no Ubuntu-specific commands: it only runs
# Odin, which is why it is build_linux.sh, not build_ubuntu.sh.
# Install Odin first on Ubuntu with ./install_ubuntu.sh
# (or the equivalent download for your distribution).
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

odin build src -out:odin-microui

echo "Built: ./odin-microui"
echo "Run: ./odin-microui"
