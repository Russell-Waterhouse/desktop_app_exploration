#!/usr/bin/env bash
# Install the build dependencies for cpp-gtk4 on Fedora.
# Fedora equivalent of install_dependencies_ubuntu.sh.
# Run this once on a new machine, then build with ./build_linux.sh.
#
# Not yet tested on Fedora: the package names below are the
# Fedora equivalents of the Ubuntu packages in
# install_dependencies_ubuntu.sh (cmake -> cmake, g++ -> gcc-c++,
# libgtk-4-dev -> gtk4-devel, libsqlite3-dev -> sqlite-devel,
# pkg-config -> pkgconf-pkg-config, git -> git).
#
# Unlike apt, dnf has no separate update step: dnf install
# refreshes repository metadata as needed. The install is
# wrapped in `timeout` (coreutils, present on Fedora too), for
# the same reason the Ubuntu script wraps apt: a hung repo
# should fail fast after 10 minutes instead of hanging forever.
set -euo pipefail

# Use sudo when not running as root.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

$SUDO timeout 600 dnf install -y \
    cmake \
    gcc-c++ \
    git \
    gtk4-devel \
    sqlite-devel \
    pkgconf-pkg-config

echo "Dependencies installed. Build with ./build_linux.sh"
