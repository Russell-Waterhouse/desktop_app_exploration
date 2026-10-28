#!/usr/bin/env bash
# Install Rust 1.99.1 and the build/run dependencies for rust-egui on Ubuntu.
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
set -euo pipefail

RUST_VERSION="1.99.1"

# Use sudo when not running as root.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

# apt can briefly be locked by another process; retry a few times
# rather than failing on the first attempt. Retries alone do not
# help a hung mirror: a hung apt-get update never exits, so it
# never reaches the retry. On Oct 27, 2026, apt-get update hung
# for 12+ minutes on the mirror.cogentco.com fallback listed in
# that VM's ubuntu.sources (azure.archive.ubuntu.com first,
# cogentco second), while Azure itself worked. So update (and
# install, below) are wrapped in `timeout` (coreutils, always
# present on Ubuntu): a hung run is killed after 5 minutes for
# update / 10 minutes for install, the retry loop then runs,
# and the script fails fast instead of hanging forever. This
# deliberately does NOT rewrite apt sources or pick a mirror:
# sources are set by the machine's image, and rewriting them
# is destructive (and cloud-init can undo it).
for attempt in 1 2 3 4 5; do
    if $SUDO timeout 300 apt-get update; then
        break
    fi
    echo "apt-get update failed or timed out, retrying in 20s (attempt $attempt/5)..." >&2
    sleep 20
done

# curl downloads rustup below, git is for the repo checkout itself,
# build-essential provides the C linker and the cc the bundled-SQLite
# build (rusqlite, bundled feature) compiles with, and pkg-config is
# what crates that probe system libraries use.
# The libxcb/libxkbcommon/libssl -dev packages are the Linux
# dependencies eframe 0.37.0 lists. Two more are runtime needs found
# while running this app in a VM under Xvfb on Oct 27, 2026: wgpu
# needed mesa-vulkan-drivers (llvmpipe) for a Vulkan device, and
# winit loads libxkbcommon-x11 at runtime, so the -dev package (which
# pulls the runtime library in) is installed rather than relying on
# it already being present.
$SUDO timeout 600 apt-get install -y \
    curl \
    git \
    build-essential \
    pkg-config \
    libxcb-render0-dev \
    libxcb-shape0-dev \
    libxcb-xfixes0-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libssl-dev \
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
