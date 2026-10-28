#!/usr/bin/env bash
# Install the toolchains and build dependencies for all seven
# recipe-manager stacks on Fedora. Run this once on a new machine,
# then build with ./build_all_linux.sh.
#
# This wrapper only runs the per-stack Fedora install scripts, in
# the same order as build_all_linux.sh builds the stacks. Run it as
# your own user, not with sudo: the per-stack scripts use sudo
# themselves, and only for the system packages, while the Rust
# toolchain installs per-user with rustup into $HOME/.cargo.
#
# Running both Rust scripts and both Odin scripts is safe: each
# one installs the same pinned toolchain (Rust 1.99.1, Odin
# dev-2026-10), and skips its toolchain download when that version
# is already installed. The system-package installs are repeated
# but idempotent.
#
# Not yet tested on Fedora: the per-stack Fedora scripts
# themselves are not yet tested on Fedora (see their headers),
# and this wrapper was not run before it was pushed.
#
# Stops at the first stack whose install fails, so a failure is
# not hidden behind later successes.
set -euo pipefail

# Run from the repository root, so this works from anywhere.
cd "$(dirname "$0")"

echo "=== rust-egui ==="
./rust-egui/install_fedora.sh

echo "=== rust-iced ==="
./rust-iced/install_fedora.sh

echo "=== cpp-imgui ==="
./cpp-imgui/install_dependencies_fedora.sh

echo "=== cpp-gtk4 ==="
./cpp-gtk4/install_dependencies_fedora.sh

echo "=== odin-raygui ==="
./odin-raygui/install_fedora.sh

echo "=== odin-microui ==="
./odin-microui/install_fedora.sh

echo "=== zig-dvui ==="
./zig-dvui/install_fedora.sh

echo "Installed dependencies for all stacks. Build with ./build_all_linux.sh"
