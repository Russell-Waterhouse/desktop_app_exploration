#!/usr/bin/env bash
# Build electron-react on Linux: install npm dependencies, then
# build the React renderer with Vite.
# This script contains no Ubuntu-specific commands: it only runs
# npm and Vite, which is why it is build_linux.sh, not
# build_ubuntu.sh. Install Node 24 and the Electron system
# libraries first on Ubuntu with ./install_ubuntu.sh (or the
# equivalent for your distribution).
#
# After building, run the app with:
#   npm start
# (which runs `electron .`; the main process loads the built
# renderer from dist/renderer/index.html).
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
    echo "node is missing: run ./install_ubuntu.sh (or install_fedora.sh) first." >&2
    exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
    echo "npm is missing: run ./install_ubuntu.sh (or install_fedora.sh) first." >&2
    exit 1
fi

# npm ci installs exactly what package-lock.json pins, so the
# build is reproducible; use it rather than npm install, which
# would resolve fresh versions.
npm ci
npm run build

echo "Built: ./dist/renderer/index.html"
echo "Run: npm start"
