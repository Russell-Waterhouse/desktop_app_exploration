# zig-dvui

Zig + DVUI version of the recipe manager test app, currently
the recipe view: a 900x600 window titled "Recipe Manager".

DVUI's current main is tested with Zig v0.17.0, so that version
is pinned in `install_ubuntu.sh`, `install_fedora.sh`, and in
`build.zig.zon`.
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

Fedora (not yet tested here — `install_fedora.sh` is the Fedora
equivalent of `install_ubuntu.sh`):

```sh
./install_fedora.sh
./build_linux.sh
./zig-out/bin/zig-dvui
```

`zig-out/`, `.zig-cache/` and `zig-pkg/` are git-ignored.

## Recipe view

Hard-coded data for now, matching the Rust version's seed:
Banana Bread, Tomato Basil Pasta, and Chicken Stir Fry
(19 ingredients, 13 steps total). No disk or network yet.

- Left pane: "Recipes", a title search box, and one button
  per matching recipe. The selected recipe is marked "> ".
  The search filters the list only; the detail keeps showing
  the selected recipe even if it no longer matches the filter.
- Right pane (scrollable): detail for the selected recipe —
  description, servings, "[No image yet]",
  ingredients, numbered steps, and notes.

## Code

- `src/main.zig` — a minimal `dvui.App`: `dvui_app` with
  `frameFn = appFrame`, which draws the two-pane recipe UI
  above. `main`, `panic` and the log function are all
  DVUI's App-provided ones. Recipe data is a `const` array
  in this file; the search text and selection are the only
  mutable frame state.
- `build.zig` — `b.dependency("dvui", .{ .backend = .sdl2 })`
  and imports `dvui_dep.module("dvui_sdl2")` as `"dvui"`.

## AI-agent VM workaround

`build_ubuntu_ai_agent_vm_hacky.sh` is VM-only and hacky: it
reproduces, with comments, everything that was needed to build
this in the author's AI-agent VM, where Zig's own fetch does not
use the egress proxy, `/tmp` is a 512M tmpfs, and the package
manager computes a different hash for the SDL 3.4.18 tarball
than the SDL3 package's manifest. It clones every DVUI
dependency with git (or downloads its tarball with curl), feeds
them to Zig's cache with local `zig fetch` calls (from a copy
without `.git` for packages with no `build.zig.zon`, or with
`.paths = .{""}`, whose local fetch would otherwise include
`.git` in the hash), builds once, patches the generated
`zig-pkg/` copy of the SDL3 zon with the package manager's
hash, and builds again. With `RUN_WINDOW=1` it also runs the
app under Xvfb and screenshots it. Do not use it on a normal
machine — use `install_ubuntu.sh` + `build_linux.sh` there.
