#!/usr/bin/env bash
# Install the build dependencies for cpp-imgui on Ubuntu.
# Run this once on a new VM, then build with ./build_linux.sh.
set -euo pipefail

# Use sudo when not running as root.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

# apt can briefly be locked by another process; retry a few times
# rather than failing on the first attempt.
for attempt in 1 2 3 4 5; do
    if $SUDO apt-get update; then
        break
    fi
    echo "apt-get update failed, retrying in 20s (attempt $attempt/5)..." >&2
    sleep 20
done

$SUDO apt-get install -y \
    cmake \
    g++ \
    git \
    libsdl2-dev \
    libgl1-mesa-dev \
    libsqlite3-dev

echo "Dependencies installed. Build with ./build_linux.sh"
