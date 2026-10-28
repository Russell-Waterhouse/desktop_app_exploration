#!/usr/bin/env bash
# Build rust-iced on Linux. Run install_ubuntu.sh or install_fedora.sh
# once first for the toolchain and system packages.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
cargo build

