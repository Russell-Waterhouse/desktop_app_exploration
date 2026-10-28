# odin-microui

Odin + microUI version of the recipe manager test app, currently
just a hello-world program. microUI is not wired in yet.

Odin dev-2026-10 is pinned in `install_ubuntu.sh`. microUI ships
with Odin itself as `vendor:microui`, so no extra library download
is needed for the next step, wiring up a microUI window.

## Build

Ubuntu:

```sh
./install_ubuntu.sh
./build_linux.sh
./odin-microui
```

`install_ubuntu.sh` installs clang (used by Odin to link on Linux)
and Odin dev-2026-10 to `/opt/odin`, with a wrapper at
`/usr/local/bin/odin` that sets `ODIN_ROOT=/opt/odin`. The wrapper
matters: Odin expects its `base/`, `core/` and `vendor/` folders
next to the compiler binary, so symlinking the binary alone is
not enough.

Fedora (target platform, package names only — not yet tested here):

```sh
# Same Odin dev-2026-10 release asset as install_ubuntu.sh, plus:
sudo dnf install clang curl unzip
```

The built `odin-microui` binary is git-ignored.
