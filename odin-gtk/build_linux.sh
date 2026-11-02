#!/usr/bin/env bash
# Build odin-gtk on Linux.
# This script contains no Ubuntu-specific commands: it only runs
# Odin, which is why it is build_linux.sh, not build_ubuntu.sh.
# Install Odin and the odin-gtk bindings first on Ubuntu with
# ./install_ubuntu.sh (or the equivalent for your distribution).
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

if [ ! -d third_party/odin-gtk ]; then
    echo "third_party/odin-gtk is missing: run ./install_ubuntu.sh (or install_fedora.sh) first," >&2
    echo "it fetches the odin-gtk bindings there." >&2
    exit 1
fi

odin build src -out:odin-gtk

echo "Built: ./odin-gtk"
echo "Run: ./odin-gtk"
