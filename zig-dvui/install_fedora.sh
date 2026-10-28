#!/usr/bin/env bash
# Install Zig 0.17.0 and the DVUI dependency on Fedora.
# Fedora equivalent of install_ubuntu.sh.
# DVUI's current main is tested with Zig v0.17.0, so that version is
# pinned here rather than taking whatever Fedora's packages offer.
# Run this once on a new machine, then build with ./build_linux.sh.
#
# Not yet tested on Fedora: the package names below are the
# Fedora equivalents of the Ubuntu packages in install_ubuntu.sh
# (xz-utils -> xz, libx11-dev -> libX11-devel,
# libxext-dev -> libXext-devel, libxcursor-dev -> libXcursor-devel,
# libxi-dev -> libXi-devel, libxfixes-dev -> libXfixes-devel,
# libxinerama-dev -> libXinerama-devel, libxrandr-dev -> libXrandr-devel,
# libgl1-mesa-dev -> mesa-libGL-devel; curl and git are the same).
# Unlike apt, dnf has no separate update step: dnf install
# refreshes repository metadata as needed. The install is wrapped
# in `timeout` (coreutils, present on Fedora too), for the same
# reason the Ubuntu script wraps apt: a hung repo should fail
# fast after 10 minutes instead of hanging forever.
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

ZIG_VERSION="0.17.0"

# Use sudo when not running as root.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

case "$(uname -m)" in
    x86_64)
        ZIG_ARCH="x86_64"
        ;;
    aarch64|arm64)
        ZIG_ARCH="aarch64"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

ZIG_TARBALL="zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz"
ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TARBALL}"

# curl downloads the Zig tarball, xz extracts it, git is what
# `zig fetch` uses to fetch the DVUI dependency below. The X11/GL
# packages are what DVUI's SDL2 backend builds against (system
# X11 headers, not Zig-packaged ones).
$SUDO timeout 600 dnf install -y \
    curl \
    xz \
    git \
    libX11-devel \
    libXext-devel \
    libXcursor-devel \
    libXi-devel \
    libXfixes-devel \
    libXinerama-devel \
    libXrandr-devel \
    mesa-libGL-devel

# Install Zig, unless exactly this version is already installed.
if command -v zig >/dev/null 2>&1 && [ "$(zig version)" = "$ZIG_VERSION" ]; then
    echo "Zig $ZIG_VERSION is already installed, skipping download."
else
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT
    echo "Downloading $ZIG_URL ..."
    curl -fsSL -o "$TMPDIR/$ZIG_TARBALL" "$ZIG_URL"
    $SUDO rm -rf /opt/zig
    $SUDO mkdir -p /opt/zig
    $SUDO tar -xf "$TMPDIR/$ZIG_TARBALL" --strip-components=1 -C /opt/zig
    $SUDO ln -sf /opt/zig/zig /usr/local/bin/zig
    if [ "$(zig version)" != "$ZIG_VERSION" ]; then
        echo "Zig install check failed: expected $ZIG_VERSION, got $(zig version)" >&2
        exit 1
    fi
fi

# Add the DVUI dependency to build.zig.zon (and download it into
# Zig's cache). Pinned to DVUI main at commit f85184497c5d231e398344d288d6626e9d6d792c
# (2026-10-27, the current main tested with Zig 0.17.0), so re-running
# this keeps the same entry instead of tracking a moving main.
# The committed build.zig.zon already contains this same entry, so
# this is a re-fetch, not a change, on a fresh checkout.
# Note: the next build will also fetch DVUI's own dependencies, so
# that build needs network access.
zig fetch --save "git+https://github.com/david-vanderson/dvui#f85184497c5d231e398344d288d6626e9d6d792c"

echo "Installed: zig $(zig version)"
echo "DVUI dependency is in build.zig.zon. Build with ./build_linux.sh"
