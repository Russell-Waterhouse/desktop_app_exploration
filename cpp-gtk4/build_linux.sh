#!/usr/bin/env bash
# Build cpp-gtk4 on Linux.
# This script contains no Ubuntu-specific commands: it only runs
# CMake, which is why it is build_linux.sh, not build_ubuntu.sh.
# Install dependencies first on Ubuntu with
# ./install_dependencies_ubuntu.sh (or the equivalent packages
# for your distribution).
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

cmake -S . -B build
cmake --build build

echo "Built: ./build/cpp-gtk4"
echo "Run: ./build/cpp-gtk4"
