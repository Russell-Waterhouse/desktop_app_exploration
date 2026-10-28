#!/usr/bin/env bash
# Install Odin dev-2026-10 on Ubuntu.
# Run this once on a new machine, then build with ./build_linux.sh.
#
# Odin is installed to /opt/odin, with its base/, core/ and vendor/
# folders kept next to the compiler binary, as Odin expects. A small
# wrapper at /usr/local/bin/odin points at it and sets ODIN_ROOT, so
# `odin` works from any directory even though only the wrapper is on
# the PATH. (Symlinking the binary alone is not enough: Odin looks
# for its library folders next to the executable it runs.)
#
# Odin uses clang to link on Linux, so clang is installed too.
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

ODIN_VERSION="dev-2026-10"

# Use sudo when not running as root.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

case "$(uname -m)" in
    x86_64|amd64)
        ODIN_ARCH="amd64"
        ;;
    aarch64|arm64)
        ODIN_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

# Odin has changed its Linux release asset name between releases
# (odin-ubuntu-amd64-*.zip, then odin-linux-amd64-*.tar.gz, then
# odin-linux-amd64-*.zip), so try the plausible names in order and
# use the first one that downloads. Pinning the version above is
# what keeps the install reproducible; the name is just packaging.
ODIN_CANDIDATES=(
    "odin-linux-${ODIN_ARCH}-${ODIN_VERSION}.tar.gz"
    "odin-linux-${ODIN_ARCH}-${ODIN_VERSION}.zip"
    "odin-ubuntu-${ODIN_ARCH}-${ODIN_VERSION}.zip"
    "odin-ubuntu-${ODIN_ARCH}-${ODIN_VERSION}.tar.gz"
)

# apt can briefly be locked by another process; retry a few times
# rather than failing on the first attempt.
for attempt in 1 2 3 4 5; do
    if $SUDO apt-get update; then
        break
    fi
    echo "apt-get update failed, retrying in 20s (attempt $attempt/5)..." >&2
    sleep 20
done

# clang links Odin programs on Linux, curl downloads the release,
# unzip/tar extract it (which one depends on the asset above).
$SUDO apt-get install -y \
    clang \
    curl \
    unzip

# Skip the download if exactly this version is already installed.
if command -v odin >/dev/null 2>&1 && odin version 2>/dev/null | grep -q "$ODIN_VERSION"; then
    echo "Odin $ODIN_VERSION is already installed, skipping download."
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ARCHIVE=""
for candidate in "${ODIN_CANDIDATES[@]}"; do
    url="https://github.com/odin-lang/Odin/releases/download/${ODIN_VERSION}/${candidate}"
    echo "Trying $url ..."
    if curl -fsSL -o "$TMPDIR/$candidate" "$url"; then
        ARCHIVE="$TMPDIR/$candidate"
        break
    fi
done

if [ -z "$ARCHIVE" ]; then
    echo "Could not download Odin $ODIN_VERSION: none of the release assets were found." >&2
    echo "Tried: ${ODIN_CANDIDATES[*]}" >&2
    exit 1
fi

# Extract straight into /opt/odin (the archive itself, ~70 MB, is the
# only thing kept in the temp dir, so this stays well clear of a
# small /tmp). Some assets wrap everything in one top-level folder;
# flatten that case so odin, base/, core/ and vendor/ land in /opt/odin.
$SUDO rm -rf /opt/odin
$SUDO mkdir -p /opt/odin
case "$ARCHIVE" in
    *.tar.gz) $SUDO tar -xf "$ARCHIVE" -C /opt/odin ;;
    *.zip)    $SUDO unzip -q "$ARCHIVE" -d /opt/odin ;;
    *)        echo "Unknown archive type: $ARCHIVE" >&2; exit 1 ;;
esac
if [ ! -x /opt/odin/odin ]; then
    subdir="$(find /opt/odin -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -n "$subdir" ] && [ -x "$subdir/odin" ]; then
        $SUDO sh -c "cp -a '$subdir'/.[!.]* '$subdir'/* /opt/odin/ 2>/dev/null || true"
        $SUDO rm -rf "$subdir"
    fi
fi
if [ ! -x /opt/odin/odin ]; then
    echo "Odin binary not found in /opt/odin after extraction." >&2
    exit 1
fi

# Wrapper, not a symlink: see the header comment about ODIN_ROOT.
$SUDO tee /usr/local/bin/odin >/dev/null <<'EOF'
#!/bin/sh
# Installed by desktop_app_exploration/odin-microui/install_ubuntu.sh
exec env ODIN_ROOT=/opt/odin /opt/odin/odin "$@"
EOF
$SUDO chmod +x /usr/local/bin/odin

if ! odin version 2>/dev/null | grep -q "$ODIN_VERSION"; then
    echo "Odin install check failed: expected $ODIN_VERSION, got:" >&2
    odin version >&2 || true
    exit 1
fi

echo "Installed: $(odin version)"
echo "microUI ships with Odin as vendor:microui, so no extra library download is needed for the next step. Build with ./build_linux.sh"
