#!/usr/bin/env bash
# Install Node.js 24 LTS and the Electron system libraries on Ubuntu.
# Run this once on a new machine, then build with ./build_linux.sh.
#
# Electron 45 bundles Chromium 156 and Node 24.22, so Node 24 is
# required: Ubuntu 24.04's own nodejs package is too old (Node 18),
# so a missing or too-old Node is installed from NodeSource's
# Node 24.x apt repository. An existing Node 24 or newer is left
# alone. npm comes with the NodeSource nodejs package.
#
# The system libraries below are what Electron's bundled Chromium
# links against on Linux (GTK3, NSS, ATK, GBM, ALSA, and the X11
# pieces). Ubuntu 24.04 renamed six of them with a t64 suffix
# after the 64-bit time_t transition, so the t64 names are used
# here; on Ubuntu 22.04 the same libraries have no suffix.
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
# is destructive (and cloud-init can undo it). The timeouts
# are generous on purpose: a normal update here takes well
# under a minute, so 5 minutes is a hang, not a slow network.
apt_update() {
    for attempt in 1 2 3 4 5; do
        if $SUDO timeout 300 apt-get update; then
            return 0
        fi
        echo "apt-get update failed or timed out, retrying in 20s (attempt $attempt/5)..." >&2
        sleep 20
    done
    echo "apt-get update failed after 5 attempts." >&2
    return 1
}

node_major() {
    if command -v node >/dev/null 2>&1; then
        node --version | sed -E 's/^v([0-9]+)\..*/\1/'
    else
        echo 0
    fi
}

# Node 24 LTS from NodeSource when the installed Node is
# missing or too old. The setup script adds the NodeSource
# apt repository and runs apt-get update itself; the install
# below then picks up nodejs from it.
if [ "$(node_major)" -ge "$NODE_MAJOR_REQUIRED" ]; then
    echo "Node $(node --version) already installed, skipping NodeSource."
else
    echo "Installing Node.js $NODE_MAJOR_REQUIRED LTS from NodeSource..."
    apt_update
    $SUDO timeout 600 apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://deb.nodesource.com/setup_24.x | $SUDO -E bash -
    $SUDO timeout 600 apt-get install -y nodejs
fi

if [ "$(node_major)" -lt "$NODE_MAJOR_REQUIRED" ]; then
    echo "Node install check failed: expected Node $NODE_MAJOR_REQUIRED or newer, got $(node --version 2>/dev/null || echo none)." >&2
    exit 1
fi

# Electron system libraries (see the header comment). curl and
# git are build tools: curl downloads NodeSource's setup script
# above, git is what a fresh checkout needs; ca-certificates is
# what curl needs to verify HTTPS.
apt_update
$SUDO timeout 600 apt-get install -y \
    ca-certificates \
    curl \
    git \
    libgtk-3-0t64 \
    libnss3 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libgbm1 \
    libasound2t64 \
    libxtst6 \
    libcups2t64 \
    libdrm2 \
    libxkbcommon0 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0t64 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libxrender1 \
    libx11-xcb1 \
    libxcb-dri3-0 \
    libxss1 \
    libnotify4 \
    libsecret-1-0 \
    xdg-utils

echo "Installed: Node $(node --version), npm $(npm --version)"
echo "Build with ./build_linux.sh"
