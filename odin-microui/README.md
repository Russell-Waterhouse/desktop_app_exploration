# odin-microui

Odin + microUI version of the recipe manager test app, currently
a recipe view with static data: a left pane listing recipes with
a title search box, and a right pane showing the selected
recipe's detail (description, servings/prep/cook, "[No image
yet]", ingredients, numbered steps, notes).

microUI ships with Odin itself as `vendor:microui`, and it does
no drawing itself: it measures text and emits draw commands, and
`src/main.odin` renders those commands with raylib
(`vendor:raylib`, whose prebuilt Linux library ships with Odin
too, and whose default font is used, so no font file is needed).
The raylib window is 900x600, titled "Recipe Manager", matching
the Rust version's window size.

## UI

- **Recipes pane** (left): a search box, then one button per
  recipe whose title contains the search text, case-insensitively
  (empty search shows all). The selected recipe is marked with
  a `> ` prefix. Filtering the list does not change the
  selection, so the detail pane keeps showing the selected recipe
  even when it is filtered out, like the Rust version.
- **Detail pane** (right): title, description, servings/prep/cook,
  "[No image yet]", ingredients, numbered steps, notes. Long
  description, step and note text is wrapped by hand in
  `src/main.odin` (`draw_wrapped`, using raylib's MeasureText),
  because microUI's own text wrapping did not line up with
  raylib's default-font measurements and clipped long lines.
  Panes can be dragged and resized; their close buttons are
  disabled so a pane cannot be lost by clicking its X. Content
  taller than a pane scrolls with the mouse wheel.
- **Data**: `src/recipes.odin` holds the same static data as the
  Rust version's seed data — Banana Bread, Tomato Basil Pasta,
  Chicken Stir Fry (19 ingredients, 13 steps total). The
  ingredient/step arrays are package-level globals that recipes
  hold slices into, deliberately: a slice literal built inside a
  procedure is backed by that procedure's stack frame in Odin,
  so building the recipes in a function corrupted them once it
  returned.

Not yet: add/edit/delete, SQLite, images, or any network/JSON
work. This is the static-data recipe-view step.

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
