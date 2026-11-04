#!/usr/bin/env bash
# Build all nine recipe-manager stacks on Linux.
# Run install_all_fedora.sh (or the per-stack install scripts for
# your distribution) once first for the toolchains and system
# packages, then run this script from the repository root.
#
# Each stack is built with its own build_linux.sh, which runs from
# its own directory, so this wrapper works from anywhere.
#
# Stops at the first stack that fails to build, so a failure is
# not hidden behind later successes.
set -euo pipefail

# Run from the repository root, so this works from anywhere.
cd "$(dirname "$0")"

echo "=== rust-egui ==="
./rust-egui/build_linux.sh

echo "=== rust-iced ==="
./rust-iced/build_linux.sh

echo "=== cpp-imgui ==="
./cpp-imgui/build_linux.sh

echo "=== cpp-gtk4 ==="
./cpp-gtk4/build_linux.sh

echo "=== odin-raygui ==="
./odin-raygui/build_linux.sh

echo "=== odin-microui ==="
./odin-microui/build_linux.sh

echo "=== zig-dvui ==="
./zig-dvui/build_linux.sh

echo "=== odin-gtk ==="
./odin-gtk/build_linux.sh

echo "=== zig-gobject ==="
./zig-gobject/build_linux.sh

echo "All stacks built."
