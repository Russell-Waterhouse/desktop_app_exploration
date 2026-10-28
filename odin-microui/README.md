# odin-microui

Odin + microUI version of the recipe manager test app, currently
a window with a microUI panel that says "Hello, world!".

microUI ships with Odin itself as `vendor:microui`, and it does
no drawing itself: it measures text and emits draw commands, and
`src/main.odin` renders those commands with raylib
(`vendor:raylib`, whose prebuilt Linux library ships with Odin
too, and whose default font is used, so no font file is needed).
The raylib window is 800x600; inside it, a microUI window titled
"Hello world" at 50,50, 400x200, holds a "Hello, world!" label.
The microUI window can be dragged by its title bar, closed with
its X, and resized from its bottom-right corner, like any
microUI window.

Odin dev-2026-10 is pinned in `install_ubuntu.sh`.

## Build

Ubuntu:

```sh
./install_ubuntu.sh
./build_linux.sh
./odin-microui
```

`install_ubuntu.sh` installs clang (used by Odin to link on Linux),
X11/GL development files (used by the raylib window), and Odin
dev-2026-10 to `/opt/odin`, with a wrapper at
`/usr/local/bin/odin` that sets `ODIN_ROOT=/opt/odin`. The wrapper
matters: Odin expects its `base/`, `core/` and `vendor/` folders
next to the compiler binary, so symlinking the binary alone is
not enough.

Fedora (target platform, package names only — not yet tested here):

```sh
# Same Odin dev-2026-10 release asset as install_ubuntu.sh, plus:
sudo dnf install clang curl unzip libX11-devel mesa-libGL-devel
```

The built `odin-microui` binary is git-ignored.
