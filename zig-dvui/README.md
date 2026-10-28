# zig-dvui

Zig + DVUI version of the recipe manager test app, currently
just a hello-world program. DVUI is not wired in yet.

DVUI's current main is tested with Zig v0.17.0, so that version
is pinned in `install_ubuntu.sh` and in `build.zig.zon`.

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
The committed `build.zig.zon` has no dependencies yet, because
adding DVUI there would make even this hello-world build fetch
DVUI's own dependencies (SDL, translate-c, etc.). The hello-world
program itself does not use DVUI yet; the install script puts
that dependency in place for the next step, wiring up a DVUI
window. Once DVUI is in `build.zig.zon`, the next build will
fetch DVUI's dependencies too, so it needs network access.

Fedora (target platform, package names only — not yet tested here):

```sh
# Same Zig 0.17.0 tarball as install_ubuntu.sh, plus:
sudo dnf install curl xz git
```

`zig-out/` and `.zig-cache/` are git-ignored.
