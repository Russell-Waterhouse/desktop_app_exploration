#!/usr/bin/env bash
# Install Node.js 24 LTS and the Electron system libraries on Fedora.
# Fedora equivalent of install_ubuntu.sh.
# Run this once on a new machine, then build with ./build_linux.sh.
#
# Electron 45 bundles Chromium 156 and Node 24.22, so Node 24 is
# required. A missing or too-old Node is installed from
# NodeSource's Node 24.x dnf repository; an existing Node 24 or
# newer is left alone. npm comes with the NodeSource nodejs
# package.
#
# The system libraries below are the Fedora equivalents of the
# Ubuntu packages in install_ubuntu.sh (libgtk-3-0t64 -> gtk3,
# libnss3 -> nss, libasound2t64 -> alsa-lib, and so on).
#
# Not yet tested on Fedora: the package names below are the
# Fedora equivalents of the Ubuntu packages in install_ubuntu.sh.
# Unlike apt, dnf has no separate update step: dnf install
# refreshes repository metadata as needed. The install is wrapped
# in `timeout` (coreutils, present on Fedora too), for the same
# reason the Ubuntu script wraps apt: a hung repo should fail
# fast after 10 minutes instead of hanging forever.
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

NODE_MAJOR_REQUIRED=24

# Use sudo when not running as root.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

node_major() {
    if command -v node >/dev/null 2>&1; then
        node --version | sed -E 's/^v([0-9]+)\..*/\1/'
    else
        echo 0
    fi
}

# Node 24 LTS from NodeSource when the installed Node is
# missing or too old. The setup script adds the NodeSource
# dnf repository; the install below then picks up nodejs
# from it.
if [ "$(node_major)" -ge "$NODE_MAJOR_REQUIRED" ]; then
    echo "Node $(node --version) already installed, skipping NodeSource."
else
    echo "Installing Node.js $NODE_MAJOR_REQUIRED LTS from NodeSource..."
    $SUDO timeout 600 dnf install -y ca-certificates curl gnupg2
    curl -fsSL https://rpm.nodesource.com/setup_24.x | $SUDO bash -
    $SUDO timeout 600 dnf install -y nodejs
fi

if [ "$(node_major)" -lt "$NODE_MAJOR_REQUIRED" ]; then
    echo "Node install check failed: expected Node $NODE_MAJOR_REQUIRED or newer, got $(node --version 2>/dev/null || echo none)." >&2
    exit 1
fi

# Electron system libraries (see the header comment). curl and
# git are build tools: curl downloads NodeSource's setup script
# above, git is what a fresh checkout needs.
$SUDO timeout 600 dnf install -y \
    ca-certificates \
    curl \
    git \
    gtk3 \
    nss \
    atk \
    at-spi2-atk \
    mesa-libgbm \
    alsa-lib \
    libXtst \
    cups-libs \
    libdrm \
    libxkbcommon \
    pango \
    cairo \
    at-spi2-core \
    libXcomposite \
    libXdamage \
    libXfixes \
    libXrandr \
    libXrender \
    libxcb \
    libXScrnSaver \
    libnotify \
    libsecret \
    xdg-utils

echo "Installed: Node $(node --version), npm $(npm --version)"
echo "Build with ./build_linux.sh"
