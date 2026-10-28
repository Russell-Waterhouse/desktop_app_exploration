#!/usr/bin/env bash
# build_ubuntu_ai_agent_vm_hacky.sh
#
# VM-ONLY, HACKY, DO NOT USE ON A NORMAL MACHINE.
#
# This script reproduces, step by step, everything that was needed
# to get the zig-dvui hello-world window to build and run inside
# the author's AI-agent VM (Ubuntu, Oct 2026). On a normal machine
# with direct internet access, you do NOT need any of this: just
# run ./install_ubuntu.sh and then ./build_linux.sh.
#
# Why this script exists at all:
#
# 1. Zig's own fetch does not use this VM's egress proxy.
#    - git and curl DO use the proxy (https_proxy is set), so
#      cloning repos and downloading tarballs with them works.
#    - `zig fetch <git-url>` and `zig build` fetching a package
#      from a URL do NOT: they fail with
#      "unable to discover remote git server capabilities:
#       HttpConnectionClosing" (for git URLs) or
#      "invalid HTTP response: HttpConnectionClosing" (for
#      tarball URLs).
#    - Workaround used here: clone every dependency with git
#      (or download its tarball with curl), then run
#      `zig fetch <local-path-or-file>`. That puts the package
#      into Zig's global cache (~/.cache/zig/p/) with exactly
#      the hash DVUI's build.zig.zon expects, so a later
#      `zig build` finds it in the cache and never touches
#      the network for that package.
#
# 2. /tmp in this VM is a 512M tmpfs.
#    - Extracting the full Zig tarball under /tmp filled it
#      ("No space left on device", then a Zig panic), so this
#      script never uses /tmp for large work. Downloads and
#      clones go under $HOME (DEPS_DIR below), and Zig itself
#      is installed to /opt/zig, as install_ubuntu.sh does.
#
# 3. `zig init` hangs in this VM, even with stdin from /dev/null.
#    - Not used here. All Zig files in this folder were written
#      by hand (build.zig, build.zig.zon, src/main.zig).
#
# 4. DVUI's package manager loads the SDL3 package even for
#    an SDL2-backend app.
#    - This project uses the SDL2 backend (.backend = .sdl2),
#      because DVUI's SDL2 Zig package builds against system
#      X11 headers, while the SDL3 backend pulls a much larger
#      Zig-package tree. Even so, `zig build` loads DVUI's
#      SDL3 package during package resolution, and that package
#      has a NON-lazy dependency on the SDL 3.4.18 upstream
#      tarball. So that tarball must be in the cache too,
#      even though the SDL3 backend is never built here.
#    - The same loading is why the script pre-populates
#      freetype, tree-sitter, svg2tvg, etc.: they ARE used by
#      the SDL2 backend (via DVUI's module), plus their own
#      transitive dependencies (zig-xml for svg2tvg, arocc
#      for translate-c).
#
# 5. The SDL tarball hash mismatch (the one genuinely hacky bit).
#    - `zig fetch` on the curl-downloaded SDL 3.4.18 tarball
#      prints exactly the hash in the SDL3 package's zon:
#        N-V-__8AACpx-AKEJIUZ0-XrP9-96MpSaw17FJ7L6B7LmO42
#      and the tarball's file contents, modes and paths match.
#    - But `zig build`'s package manager, when it fetches that
#      same tarball, computes a different hash:
#        N-V-__8AACpx-AKinNgsWiJhrLReR4ZMGScwnSSTqNHUy9mK
#      and fails with "hash mismatch" before compiling anything.
#      The cause was never pinned down in this VM (it may be
#      proxy/tarball-header related); it does not happen for
#      any of the git-cloned packages above.
#    - Workaround used here, and ONLY here: run `zig build`
#      once, let it fail at package resolution, then edit the
#      GENERATED copy of the SDL3 package's zon that the
#      package manager extracted into this project's zig-pkg/
#      directory, replacing the manifest hash with the hash
#      the package manager computed, and build again. The
#      second build succeeds and never builds the SDL3 backend.
#    - That edit touches zig-pkg/ only. zig-pkg/ is git-ignored
#      and is NOT committed. It is lost on a clean build, which
#      is why this script re-applies it on every run if needed.
#      Never edit the committed build.zig.zon files to this
#      AKin hash: on a normal machine the manifest hash is
#      the correct one.
#
# What this script does, in order:
#   a. Installs system packages (apt) and Zig 0.17.0 if needed.
#   b. Clones/downloads every DVUI dependency at its pinned
#      commit/tag and `zig fetch`es it into the global cache,
#      checking the printed hash against the expected one.
#   c. Builds with ./build_linux.sh, applying the SDL tarball
#      hash workaround on a first-build failure, then building
#      again.
#   d. Optionally (RUN_WINDOW=1) runs the app under Xvfb and
#      takes a screenshot with ffmpeg, to prove the window opens.
#
# Usage:
#   ./build_ubuntu_ai_agent_vm_hacky.sh
#   RUN_WINDOW=1 ./build_ubuntu_ai_agent_vm_hacky.sh
#
# The script is idempotent: re-running it re-clones (or fast-
# forwards) the same pinned commits, re-fetches the same hashes
# into the cache, and re-applies the zig-pkg hash edit if it is
# still needed. A full build here takes several minutes on this
# VM (slow CPU, SDL2 + freetype + tree-sitter C compilation),
# so do not mistake a long, quiet build for a hang.
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

# ------------------------------------------------------------------
# Configuration: pins. These are the exact commits/tags DVUI's
# build.zig.zon (at f8518449, 2026-10-27) expects. Changing a pin
# here without changing the corresponding hash will make the
# hash check below fail, which is the point: the check is how
# you know the cache entry matches what DVUI will ask for.
# ------------------------------------------------------------------
ZIG_VERSION="0.17.0"
DVUI_COMMIT="f85184497c5d231e398344d288d6626e9d6d792c"

# Work directory for clones/downloads. Deliberately NOT /tmp:
# /tmp is a 512M tmpfs in this VM (see header, point 2).
DEPS_DIR="${DVUI_VM_DEPS_DIR:-$HOME/dvui-vm-deps}"
mkdir -p "$DEPS_DIR"

# sudo when not running as root, as in install_ubuntu.sh.
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

# clone_pin <dir-name> <git-url> <commit> [branch]
# Clone a repo (or, if it already exists, fetch and checkout the
# pinned commit) so that `zig fetch` below sees exactly that tree.
# The optional branch is only needed for repos where the pinned
# commit lives on a non-default branch (sdl2: zig16,
# translate-c: zig-0.17.x); for the others a plain clone + fetch
# by commit works.
clone_pin() {
    local name="$1" url="$2" commit="$3" branch="${4:-}"
    local dir="$DEPS_DIR/$name"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" fetch --depth 1 origin "$commit" 2>&1 | tail -1 || true
        git -C "$dir" checkout "$commit" 2>&1 | tail -1 || true
    elif [ -n "$branch" ]; then
        git clone --branch "$branch" --depth 1 "$url" "$dir" 2>&1 | tail -1
        git -C "$dir" fetch --depth 1 origin "$commit" 2>&1 | tail -1 || true
        git -C "$dir" checkout "$commit" 2>&1 | tail -1 || true
    else
        git clone "$url" "$dir" 2>&1 | tail -1
        git -C "$dir" fetch --depth 1 origin "$commit" 2>&1 | tail -1 || true
        git -C "$dir" checkout "$commit" 2>&1 | tail -1 || true
    fi
    echo "$name: $(git -C "$dir" rev-parse HEAD)"
}

# fetch_check <path> <expected-hash>
# `zig fetch` a local path/file into the global cache and fail
# loudly if the hash it prints is not the expected one. A mismatch
# here means the cloned tree is not the tree DVUI expects, and a
# later `zig build` will fail at package resolution, so fail now
# with a clear message instead of a confusing build error.
fetch_check() {
    local path="$1" expected="$2"
    local got
    got="$(zig fetch "$path")"
    echo "fetched $path -> $got"
    if [ "$got" != "$expected" ]; then
        echo "ERROR: hash mismatch for $path: got $got, expected $expected" >&2
        exit 1
    fi
}

# fetch_check_nogit <dir-name> <expected-hash>
# Same as fetch_check, but on a copy WITHOUT the .git directory.
# Needed in two cases, and this is a lesson learned the hard way
# while testing this script (it first failed on tree-sitter-json):
#  - a package whose build.zig.zon says .paths = .{""} (all
#    files): a local `zig fetch` of a git checkout would
#    otherwise include .git/ itself in the hash and never match.
#    freetype is the one such package here.
#  - a package with NO build.zig.zon at all (the tree-sitter
#    grammar repos, which are plain C parser repos): a local
#    fetch again includes .git/, and the hash then depends on
#    the clone's .git state, so it varies from clone to clone
#    and never matches the manifest hash. The package manager,
#    fetching from a git URL, hashes only the tracked files,
#    which is exactly what a nogit copy contains.
# Packages WITH a zon whose .paths list specific files/dirs
# (dvui, sdl2, translate-c, sdl3, tree-sitter, svg2tvg,
# zig-xml, arocc) do NOT need this: their .paths already
# exclude .git, so a direct local fetch matches.
# (cp -r, not cp -a: -a fails to preserve ownership in this
# VM and would abort the script under `set -e`.)
fetch_check_nogit() {
    local name="$1" expected="$2"
    local src="$DEPS_DIR/$name" copy="$DEPS_DIR/${name}-nogit"
    rm -rf "$copy"
    cp -r "$src" "$copy"
    rm -rf "$copy/.git"
    fetch_check "$copy" "$expected"
}

# ------------------------------------------------------------------
# a. System packages and Zig
# ------------------------------------------------------------------
# Skip the apt step entirely if everything this script needs is
# already installed. This matters in this VM: apt-get update has
# been seen to hang for 12+ minutes on a slow mirror, and a
# re-run of this script does not need to re-install packages
# that are already there. On a fresh machine the else-branch
# below does the full install, exactly as install_ubuntu.sh does.
APT_PKGS="curl xz-utils git libx11-dev libxext-dev libxcursor-dev libxi-dev libxfixes-dev libxinerama-dev libxrandr-dev libgl1-mesa-dev xvfb ffmpeg"
APT_MISSING=0
for pkg in $APT_PKGS; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        APT_MISSING=1
        echo "apt package missing: $pkg"
    fi
done
if [ "$APT_MISSING" = "1" ]; then
    # apt can briefly be locked by another process; retry, as in
    # install_ubuntu.sh.
    for attempt in 1 2 3 4 5; do
        if $SUDO apt-get update; then
            break
        fi
        echo "apt-get update failed, retrying in 20s (attempt $attempt/5)..." >&2
        sleep 20
    done
    # curl/xz/git: Zig download + git clones. X11/GL dev packages:
    # DVUI's SDL2 backend builds against system X11 headers.
    # xvfb/ffmpeg: only for the optional RUN_WINDOW=1 run check.
    # shellcheck disable=SC2086
    $SUDO apt-get install -y $APT_PKGS
else
    echo "All required apt packages are already installed, skipping apt."
fi

# Install Zig 0.17.0 to /opt/zig unless exactly that version is
# already installed. Download/extract under DEPS_DIR, not /tmp.
if command -v zig >/dev/null 2>&1 && [ "$(zig version)" = "$ZIG_VERSION" ]; then
    echo "Zig $ZIG_VERSION is already installed, skipping download."
else
    case "$(uname -m)" in
        x86_64) ZIG_ARCH="x86_64" ;;
        aarch64|arm64) ZIG_ARCH="aarch64" ;;
        *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    ZIG_TARBALL="zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz"
    ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TARBALL}"
    echo "Downloading $ZIG_URL ..."
    curl -fsSL -o "$DEPS_DIR/$ZIG_TARBALL" "$ZIG_URL"
    $SUDO rm -rf /opt/zig
    $SUDO mkdir -p /opt/zig
    $SUDO tar -xf "$DEPS_DIR/$ZIG_TARBALL" --strip-components=1 -C /opt/zig
    $SUDO ln -sf /opt/zig/zig /usr/local/bin/zig
    if [ "$(zig version)" != "$ZIG_VERSION" ]; then
        echo "Zig install check failed: expected $ZIG_VERSION, got $(zig version)" >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------
# b. Pre-populate Zig's package cache from git/curl, not from
#    Zig's own HTTP client (see header, point 1).
# ------------------------------------------------------------------
# DVUI itself (pinned in this project's build.zig.zon).
clone_pin dvui https://github.com/david-vanderson/dvui "$DVUI_COMMIT"
fetch_check "$DEPS_DIR/dvui" "dvui-0.6.0-dev-AQFJmXqTBAGIFho3xAKct320CiNm-lvshf7_c1Q_Eur9"

# Non-lazy dependencies in DVUI's zon: these are fetched by the
# package manager even before any backend is chosen, so they
# must be cached first or the very first build fails.
# - sdl2: DVUI's SDL2 package (branch zig16).
clone_pin sdl2 https://github.com/david-vanderson/SDL 9243546640b45eba67d3cccc939add6039dc6c62 zig16
fetch_check "$DEPS_DIR/sdl2" "SDL-2.32.10-JToi34a4EgEYfCUCjSrKCF6Kmryc7Km9YP6k1qEyDMAz"
# - translate-c: DVUI's C translation layer (branch zig-0.17.x).
clone_pin translate_c https://codeberg.org/ziglang/translate-c 02ff0c523fb92a38939b04d0145c4a9602a74d56 zig-0.17.x
fetch_check "$DEPS_DIR/translate_c" "translate_c-2.0.0-Q_BUWltOBwBYABF84EUL208pIFeUIwbBs29FmVBaafN5"

# Lazy dependencies that the SDL2 backend actually uses, via
# DVUI's module: freetype (fonts), tree-sitter (+ its JSON and
# Zig grammars, used by DVUI's text handling), and svg2tvg
# (TVG icon rendering, tvg is on by default).
clone_pin sdl3 https://github.com/allyourcodebase/SDL 26ea74f20ed8c80b0ed0027bc0a7684967cdc243
fetch_check "$DEPS_DIR/sdl3" "sdl-1.0.6+3.4.18-i4QD0eENqgBF05QqwFxQm937mtl5sNDidtSmvG38hHKz"
clone_pin freetype https://github.com/david-vanderson/freetype 4938878b58e8481bc11ac52d6fe10a7cf6c3c7d5
fetch_check_nogit freetype "freetype-2.14.1-alzUkceCqgDRZIP8PnxnNCd8jwfbwY0k1VhlTV2O5Ivo"
clone_pin tree_sitter https://github.com/Yinameah/tree-sitter 67d4d7e3a9c2c0b155b13642b9d6b3ed177325e1
fetch_check "$DEPS_DIR/tree_sitter" "tree_sitter-0.28.0-Tw2sRznODQDCEzlat-s1Bb2lQeOuggNKJT_TLNaXDRZs"
clone_pin tree_sitter_json https://github.com/tree-sitter/tree-sitter-json 001c28d7a29832b06b0e831ec77845553c89b56d
fetch_check_nogit tree_sitter_json "N-V-__8AAHNaAgD6kjK3HX6lAf89chPqS5zIm0tLpvBQLOtX"
clone_pin tree_sitter_zig https://github.com/Yinameah/tree-sitter-zig 39643900518f291a72ff8e26a3b505b5ce3c3a66
fetch_check_nogit tree_sitter_zig "tree_sitter_zig-1.1.2-YNf2GP57XABT7jXfXt3CkhXpwo-NnAVVhiMqljClr_ds"
clone_pin svg2tvg https://github.com/nat3Github/zig-lib-svg2tvg b41ef1eb5b432c9026deaad31046789247a1fe29
fetch_check "$DEPS_DIR/svg2tvg" "svg2tvg-0.0.0-HpMZuXH9BQA3K8zSdy8LfbrbuWwOYyZdvQa55n2KTCbv"

# Transitive dependencies of the packages above:
# - zig-xml: svg2tvg's dependency.
clone_pin zig_xml https://github.com/ianprime0509/zig-xml 4beab29d68ab308af4bd12a4fc4187c24fdad0d6
fetch_check "$DEPS_DIR/zig_xml" "xml-0.2.2-ZTbP35N4AgAN3HBgWmBp_LAQ0MIPKW17GAGMwx4DHGYK"
# - arocc: translate-c's dependency (named "aro" in its zon).
clone_pin arocc https://codeberg.org/ziglang/arocc d0c8c4d9c55daa7ef6e40cf0f630a5b5e900989b
fetch_check "$DEPS_DIR/arocc" "aro-0.0.0-JSD1QtuBNwCASyBtNF3pqTl_W3oAJQGEVyFAtrBSE_Pa"

# SDL3 package's non-lazy dependency, the SDL 3.4.18 upstream
# tarball. This must be cached even though the SDL3 backend is
# never built here (see header, point 4). Downloaded with curl
# because Zig's HTTP client cannot fetch it in this VM.
# Note: `zig fetch` on this file prints the manifest hash below,
# which is what the SDL3 package's zon expects. The package
# manager's different hash for the same tarball is handled in
# section c below.
curl -fsSL -o "$DEPS_DIR/sdl-3.4.18.tar.gz" \
    https://github.com/libsdl-org/SDL/archive/refs/tags/release-3.4.18.tar.gz
fetch_check "$DEPS_DIR/sdl-3.4.18.tar.gz" "N-V-__8AACpx-AKEJIUZ0-XrP9-96MpSaw17FJ7L6B7LmO42"

# ------------------------------------------------------------------
# c. Build, with the SDL tarball hash workaround if needed.
# ------------------------------------------------------------------
# First try: on a clean checkout this fails at package
# resolution with the SDL tarball hash mismatch described in
# the header (point 5). On a re-run it may already succeed,
# because zig-pkg/ still carries the workaround edit.
if ./build_linux.sh; then
    echo "Build succeeded on the first try."
else
    echo "First build failed; applying the SDL tarball hash workaround..."
    echo "This edits only the generated zig-pkg/ copy of the SDL3"
    echo "package's zon (git-ignored, never committed), replacing"
    echo "the manifest hash with the hash the package manager"
    echo "computed for the same tarball in this VM."
    SDL_MANIFEST_HASH="N-V-__8AACpx-AKEJIUZ0-XrP9-96MpSaw17FJ7L6B7LmO42"
    SDL_VM_HASH="N-V-__8AACpx-AKinNgsWiJhrLReR4ZMGScwnSSTqNHUy9mK"
    SDL3_ZON="$(ls -d zig-pkg/sdl-*/build.zig.zon 2>/dev/null | head -n 1 || true)"
    if [ -z "$SDL3_ZON" ]; then
        echo "ERROR: could not find zig-pkg/sdl-*/build.zig.zon to patch" >&2
        exit 1
    fi
    echo "Patching $SDL3_ZON"
    sed -i "s|$SDL_MANIFEST_HASH|$SDL_VM_HASH|" "$SDL3_ZON"
    # Second try: this is the build that actually compiles
    # DVUI, SDL2, freetype, tree-sitter, etc. (several minutes
    # on this VM) and produces ./zig-out/bin/zig-dvui.
    ./build_linux.sh
fi

echo "Built: ./zig-out/bin/zig-dvui"

# ------------------------------------------------------------------
# d. Optional run check: open the window under Xvfb and screenshot it.
# ------------------------------------------------------------------
if [ "${RUN_WINDOW:-0}" = "1" ]; then
    if command -v Xvfb >/dev/null 2>&1 && command -v ffmpeg >/dev/null 2>&1; then
        echo "Running the window under Xvfb for a screenshot..."
        Xvfb :99 -screen 0 1024x768x24 > /tmp/xvfb.log 2>&1 &
        XVFB_PID=$!
        sleep 2
        DISPLAY=:99 ./zig-out/bin/zig-dvui > /tmp/dvui-run.log 2>&1 &
        APP_PID=$!
        sleep 4
        DISPLAY=:99 ffmpeg -y -f x11grab -video_size 1024x768 -i :99 \
            -frames:v 1 ./zig-dvui-window.png 2>&1 | tail -3
        ls -lh ./zig-dvui-window.png
        kill "$APP_PID" "$XVFB_PID" 2>/dev/null || true
        echo "Screenshot: ./zig-dvui-window.png (should show a white"
        echo "400x300 window with 'Hello, world!' in the top left)"
    else
        echo "RUN_WINDOW=1 was set, but Xvfb or ffmpeg is not available;"
        echo "skipping the run check. Run it manually with:"
        echo "  Xvfb :99 -screen 0 1024x768x24 &"
        echo "  DISPLAY=:99 ./zig-out/bin/zig-dvui"
    fi
else
    echo "Run it with: ./zig-out/bin/zig-dvui"
    echo "Or, to also run it under Xvfb and screenshot it:"
    echo "  RUN_WINDOW=1 $0"
fi
