#!/usr/bin/env bash
# Build zig-gobject on Linux.
# This script contains no Ubuntu-specific commands: it only runs Zig,
# which is why it is build_linux.sh, not build_ubuntu.sh.
# Install Zig and generate the bindings first on Ubuntu with
# ./install_ubuntu.sh (or the equivalent for your distribution).
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

if [ ! -d third_party/bindings ]; then
    echo "third_party/bindings is missing: run ./install_ubuntu.sh (or install_fedora.sh) first," >&2
    echo "it generates the zig-gobject bindings there." >&2
    exit 1
fi

zig build

echo "Built: ./zig-out/bin/zig-gobject"
echo "Run: ./zig-out/bin/zig-gobject"
