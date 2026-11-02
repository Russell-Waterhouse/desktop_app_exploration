#!/usr/bin/env bash
# Install Zig 0.17.0 and generate the zig-gobject bindings on Fedora.
# Fedora equivalent of install_ubuntu.sh.
# Run this once on a new machine, then build with ./build_linux.sh.
#
# Zig 0.17.0 is pinned here because that is the version the
# zig-gobject generator and generated bindings are tested with.
# Zig is installed from its tarball to /opt/zig, with a symlink
# at /usr/local/bin/zig.
#
# The bindings are NOT vendored in this repo: zig-gobject
# generates them from GObject introspection data, so the install
# script clones zig-gobject (pinned to a commit below) into
# third_party/zig-gobject, runs its codegen step for Gtk-4.0,
# and copies the generated package to third_party/bindings,
# which build.zig.zon points at. Re-running the script keeps an
# existing checkout but re-runs codegen and re-copies, so the
# bindings always match the pinned generator.
#
# Not yet tested on Fedora: the package names below are the
# Fedora equivalents of the Ubuntu packages in install_ubuntu.sh
# (libgtk-4-dev -> gtk4-devel, xsltproc -> libxslt, which ships
# the xsltproc binary; curl, xz and git are the same). Unlike
# apt, dnf has no separate update step: dnf install refreshes
# repository metadata as needed. The install is wrapped in
# `timeout` (coreutils, present on Fedora too), for the same
# reason the Ubuntu script wraps apt: a hung repo should fail
# fast after 10 minutes instead of hanging forever.
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

ZIG_VERSION="0.17.0"
# zig-gobject default branch at the time this stack was set up
# (Nov 1, 2026); its README states the generator and generated
# bindings are tested on Zig 0.17.0.
ZIG_GOBJECT_COMMIT="93afca136b82d4e8d2476298529fc6f6be4bcc07"

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

# curl downloads the Zig tarball, xz extracts it, git fetches
# the zig-gobject generator below. gtk4-devel is what the
# generated bindings link against, and it also brings the
# Gtk-4.0 GIR file the generator reads. libxslt ships the
# xsltproc binary the generator uses to apply its GIR fixes:
# without it codegen fails with "failed to execute xsltproc".
# sqlite-devel is what src/db.zig links against: Zig ships no
# SQLite package, so db.zig declares the system SQLite C API
# by hand and links the system library (see the SQLite
# section in README.md). libicu-devel is what the
# text-encoding import links against: src/json_import.zig
# uses ICU via a build-time translate-c of src/icu.h, and
# links icuuc and icui18n.
$SUDO timeout 600 dnf install -y \
    curl \
    xz \
    git \
    gtk4-devel \
    libxslt \
    sqlite-devel \
    libicu-devel

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

# Fetch the generator, pinned to the commit above. A full clone
# (not --depth 1) so the pinned commit can always be checked out.
if [ ! -d third_party/zig-gobject ]; then
    git clone https://github.com/ianprime0509/zig-gobject.git third_party/zig-gobject
fi
git -C third_party/zig-gobject checkout "$ZIG_GOBJECT_COMMIT"

# Generate the bindings. GIR files live in /usr/share/gir-1.0;
# the lib-dir glob also covers distributions that split one out
# (on Ubuntu, GLib-2.0.gir is in /usr/lib/<triplet>/gir-1.0).
GIR_ARGS=()
for dir in /usr/share/gir-1.0 /usr/lib/*/gir-1.0; do
    if [ -d "$dir" ]; then
        GIR_ARGS+=("-Dgir-files-path=$dir")
    fi
done
(cd third_party/zig-gobject && zig build codegen -Dmodules=Gtk-4.0 "${GIR_ARGS[@]}")

rm -rf third_party/bindings
cp -r third_party/zig-gobject/zig-out/bindings third_party/bindings

echo "Installed: zig $(zig version)"
echo "Bindings generated in third_party/bindings. Build with ./build_linux.sh"
