# zig-dvui

Zig + DVUI version of the recipe manager test app, currently
a hello-world window: a 400x300 window titled "Hello DVUI"
showing the label "Hello, world!".

DVUI's current main is tested with Zig v0.17.0, so that version
is pinned in `install_ubuntu.sh` and in `build.zig.zon`.
The backend is SDL2 (`dvui_sdl2`): DVUI's SDL2 Zig package
builds against system X11 headers, which keeps the dependency
tree much smaller than the SDL3 backend's.

## Build

Ubuntu:

```sh
./install_ubuntu.sh
./build_linux.sh
./zig-out/bin/zig-dvui
```

`install_ubuntu.sh` installs Zig 0.17.0 to `/opt/zig` (symlinked
from `/usr/local/bin/zig`) and adds the DVUI dependency to
`build.zig.zon` with `zig fetch --save`, pinned to DVUI main at
commit `f85184497c5d231e398344d288d6626e9d6d792c` (2026-10-27).
The committed `build.zig.zon` already contains that same DVUI
entry, so on a machine with direct GitHub access the fetch in
the install script is just a re-fetch of the same pin; the
first build then also fetches DVUI's own dependencies (SDL,
translate-c, freetype, tree-sitter, svg2tvg, etc.), so it
needs network access.

Fedora (target platform, package names only — not yet tested here):

```sh
# Same Zig 0.17.0 tarball as install_ubuntu.sh, plus:
sudo dnf install curl xz git
# plus the X11/GL development packages the SDL2 backend needs
```

`zig-out/`, `.zig-cache/` and `zig-pkg/` are git-ignored.

## Code

- `src/main.zig` — a minimal `dvui.App`: `dvui_app` with
  `frameFn = appFrame`, which draws a vertical box containing
  one label. `main`, `panic` and the log function are all
  DVUI's App-provided ones.
- `build.zig` — `b.dependency("dvui", .{ .backend = .sdl2 })`
  and imports `dvui_dep.module("dvui_sdl2")` as `"dvui"`.
