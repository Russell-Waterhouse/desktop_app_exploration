#!/usr/bin/env bash
# Install Zig 0.17.0 and the DVUI dependency on Ubuntu.
# DVUI's current main is tested with Zig v0.17.0, so that version is
# pinned here rather than taking whatever Ubuntu's packages offer.
# Run this once on a new machine, then build with ./build_linux.sh.
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

# apt can briefly be locked by another process; retry a few times
# rather than failing on the first attempt.
for attempt in 1 2 3 4 5; do
    if $SUDO apt-get update; then
        break
    fi
    echo "apt-get update failed, retrying in 20s (attempt $attempt/5)..." >&2
    sleep 20
done

# curl downloads the Zig tarball, xz-utils extracts it, git is what
# `zig fetch` uses to fetch the DVUI dependency below.
$SUDO apt-get install -y \
    curl \
    xz-utils \
    git

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
# DVUI is not used by src/main.zig yet — this step just gets the
# dependency in place for the next step, wiring up a DVUI window.
# Note: once DVUI is in build.zig.zon, the next build will also fetch
# DVUI's own dependencies, so that build needs network access.
zig fetch --save "git+https://github.com/david-vanderson/dvui#f85184497c5d231e398344d288d6626e9d6d792c"

echo "Installed: zig $(zig version)"
echo "DVUI dependency is in build.zig.zon. Build with ./build_linux.sh"
