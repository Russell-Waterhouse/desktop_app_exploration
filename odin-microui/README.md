# odin-microui

Odin + microUI version of the recipe manager test app, currently
a recipe view backed by SQLite: a left pane listing recipes with
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
- **Data**: on first run the app creates `recipes.db` in the
  current working directory and seeds it once from
  `src/recipes.odin` — the same data as the Rust version's seed
  (Banana Bread, Tomato Basil Pasta, Chicken Stir Fry, 19
  ingredients, 13 steps total). Later runs load from the
  database and do not re-seed. The ingredient/step arrays in
  `recipes.odin` are package-level globals that recipes hold
  slices into, deliberately: a slice literal built inside a
  procedure is backed by that procedure's stack frame in Odin,
  so building the recipes in a function corrupted them once it
  returned.

## SQLite — the wrinkle

Odin ships no SQLite package. `vendor/` has no sqlite (unlike
`vendor:microui` and `vendor:raylib`), and `core/` has no
database package, so unlike the Rust version — which uses
rusqlite with its bundled SQLite — `src/db.odin` declares the
system SQLite C API by hand and links the system library:

```odin
foreign import sqlite3 "system:sqlite3"
```

The bindings in `db.odin` cover only what this app uses:
`sqlite3_open`, `sqlite3_close`, `sqlite3_exec`,
`sqlite3_prepare_v2`, `sqlite3_step`, `sqlite3_finalize`,
`sqlite3_column_text`/`_int`/`_int64`/`_type`,
`sqlite3_bind_text`/`_int64`/`_null`, `sqlite3_errmsg`,
`sqlite3_last_insert_rowid`, and `sqlite3_free`. Strings bound
with `SQLITE_STATIC` (a nil destructor) are heap-allocated
and live until after the step, which is all that binding
requires.

Consequences, compared with the Rust version:

- **The build needs the development package, not just the
  runtime library.** `libsqlite3-dev` on Ubuntu (and
  `sqlite-devel` on Fedora) provides the `libsqlite3.so`
  symlink and `sqlite3.h` header that linking needs; the
  runtime package alone (`libsqlite3-0`) lets a built binary
  run but not link.
- **The binary depends on the system SQLite at runtime.**
  Check with `ldd odin-microui`: it links `libsqlite3.so`,
  whereas the Rust binary's SQLite is statically bundled.
- **Schema matches Rust** (`rust-egui/src/db.rs`): recipes
  (id, title, description, servings, prep_minutes,
  cook_minutes, image_path, notes), ingredients (id, recipe_id,
  position, amount, unit, name), steps (id, recipe_id, position,
  text), foreign keys on. Seed recipes are inserted with a
  NULL `image_path`, as in Rust, until the image step sets it.
- **One connection for the app's lifetime**, closed when
  `main` returns. Rust opens a new connection per operation
  to keep borrowing simple; Odin has no borrowing rules to
  work around, so one connection is simpler here.
- **A load failure is shown, not fatal.** If opening,
  seeding, or loading fails, the detail pane shows
  "Database error:" plus the message, like the Rust version.
- `recipes.db` is git-ignored and never pushed.

Not yet: add/edit/delete, images, or any network/JSON work.
This is the SQLite step, following the Rust order (recipe view,
then SQLite, then edit/delete, then images).

Odin dev-2026-10 is pinned in `install_ubuntu.sh` and
`install_fedora.sh`.

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

Fedora (not yet tested here — `install_fedora.sh` is the Fedora
equivalent of `install_ubuntu.sh`):

```sh
./install_fedora.sh
./build_linux.sh
./odin-microui
```

The built `odin-microui` binary and `recipes.db` are git-ignored.
