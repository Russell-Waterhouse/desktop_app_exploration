#!/usr/bin/env bash
# Install the build dependencies for cpp-gtk4 on Ubuntu.
# Run this once on a new VM, then build with ./build_linux.sh.
set -euo pipefail

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
for attempt in 1 2 3 4 5; do
    if $SUDO timeout 300 apt-get update; then
        break
    fi
    echo "apt-get update failed or timed out, retrying in 20s (attempt $attempt/5)..." >&2
    sleep 20
done

$SUDO timeout 600 apt-get install -y \
    cmake \
    g++ \
    git \
    libgtk-4-dev \
    libsqlite3-dev \
    pkg-config

echo "Dependencies installed. Build with ./build_linux.sh"
