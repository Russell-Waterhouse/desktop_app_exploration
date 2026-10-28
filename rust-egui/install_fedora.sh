#!/usr/bin/env bash
# Install Rust 1.99.1 and the build/run dependencies for rust-egui on Fedora.
# Fedora equivalent of install_ubuntu.sh.
# Run this once on a new machine, then build from rust-egui/ with `cargo build`.
#
# Rust itself is installed per-user with rustup (into $HOME/.cargo), so run
# this script as your own user, not with sudo: only the system packages
# below use sudo, and only when the script is not already running as root.
# The Rust version is pinned, like Zig and Odin are in their install
# scripts, rather than tracking the moving stable channel: 1.99.1 is the
# version this project (eframe 0.37.0) was built and verified with on
# Oct 27, 2026. Re-running the script keeps that version instead of
# silently moving to a newer toolchain.
#
# Not yet tested on Fedora: the package names below are the
# Fedora equivalents of the Ubuntu packages in install_ubuntu.sh
# (build-essential -> gcc, pkg-config -> pkgconfig,
# libxcb-render0-dev/libxcb-shape0-dev/libxcb-xfixes0-dev ->
# libxcb-devel, libxkbcommon-dev -> libxkbcommon-devel,
# libxkbcommon-x11-dev -> libxkbcommon-x11-devel,
# libssl-dev -> openssl-devel, mesa-vulkan-drivers ->
# mesa-vulkan-drivers; curl and git are the same).
#
# Unlike apt, dnf has no separate update step: dnf install
# refreshes repository metadata as needed. The install is wrapped
# in `timeout` (coreutils, present on Fedora too), for the same
# reason the Ubuntu script wraps apt: a hung repo should fail
# fast after 10 minutes instead of hanging forever.
set -euo pipefail

RUST_VERSION="1.99.1"

# Use sudo when not running as root.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

# curl downloads rustup below, git is for the repo checkout itself,
# gcc provides the C linker and the cc the bundled-SQLite build
# (rusqlite, bundled feature) compiles with, and pkgconfig is what
# crates that probe system libraries use.
# The libxcb/libxkbcommon/openssl -devel packages are the Fedora
# equivalents of the Linux dependencies eframe 0.37.0 lists for
# Ubuntu. Two more are runtime needs found while running this app
# in a VM under Xvfb on Oct 27, 2026: wgpu needed mesa-vulkan-drivers
# (llvmpipe) for a Vulkan device, and winit loads libxkbcommon-x11
# at runtime, so the -devel package (which pulls the runtime
# library in) is installed rather than relying on it already being
# present.
$SUDO timeout 600 dnf install -y \
    curl \
    git \
    gcc \
    pkgconfig \
    libxcb-devel \
    libxkbcommon-devel \
    libxkbcommon-x11-devel \
    openssl-devel \
    mesa-vulkan-drivers

# rustup puts cargo/rustc in $HOME/.cargo/bin and writes an env file
# there; source it if it exists so a rustup installed by an earlier
# run (or by hand) is found even if this shell has not picked it up.
if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
fi

# Install the pinned toolchain, unless exactly this version is
# already installed. If rustup is already present, use it to add the
# toolchain; otherwise install rustup itself (non-interactively,
# minimal profile) pinned to this toolchain. No sudo here: rustup
# installs into the invoking user's $HOME/.cargo.
if command -v rustc >/dev/null 2>&1 && [ "$(rustc --version | cut -d' ' -f2)" = "$RUST_VERSION" ]; then
    echo "Rust $RUST_VERSION is already installed, skipping download."
elif command -v rustup >/dev/null 2>&1; then
    rustup toolchain install "$RUST_VERSION"
    rustup default "$RUST_VERSION"
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION"
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.cargo/env"
    fi
fi

if ! command -v rustc >/dev/null 2>&1 || [ "$(rustc --version | cut -d' ' -f2)" != "$RUST_VERSION" ]; then
    echo "Rust install check failed: expected $RUST_VERSION, got: $(rustc --version 2>/dev/null || echo 'rustc not found')" >&2
    exit 1
fi

echo "Installed: $(rustc --version), $(cargo --version)"
echo "Build from rust-egui/ with: cargo build"
