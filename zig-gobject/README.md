# zig-gobject

Zig + GTK4 version of the recipe manager test app, using the
ianprime0509/zig-gobject bindings (GObject-introspection-generated
bindings to GTK4 and libadwaita). This stack stands on the same
Pango text stack as cpp-gtk4, so displayed text shaping and
label selectability come from GTK itself rather than from code
in this app.

## Bindings

The bindings are NOT vendored in this repo: zig-gobject
generates them from GObject introspection (GIR) data, so
install_ubuntu.sh and install_fedora.sh clone zig-gobject
(pinned to commit 93afca136b82d4e8d2476298529fc6f6be4bcc07)
into third_party/zig-gobject, run its codegen step for
Gtk-4.0, and copy the generated package to
third_party/bindings, which build.zig.zon points at.
Re-running the script keeps the existing checkout but
re-runs codegen and re-copies, so the bindings always match
the pinned generator. The generated bindings link against
the system GTK libraries.

Two codegen gotchas, both handled by the install scripts:

- The generator applies its GIR fixes with the `xsltproc`
  binary: the libxslt runtime alone is not enough, so the
  scripts install xsltproc (Ubuntu) / libxslt (Fedora,
  which ships the binary). Without it codegen fails with
  "failed to execute xsltproc".
- GIR files live in /usr/share/gir-1.0, except on Ubuntu,
  where GLib-2.0.gir is in the multiarch lib dir
  (/usr/lib/<triplet>/gir-1.0) instead, so the scripts pass
  both locations (found by glob, so any arch works).

## Build

Ubuntu:

```sh
./install_ubuntu.sh
./build_linux.sh
./zig-out/bin/zig-gobject
```

`install_ubuntu.sh` installs Zig 0.17.0 to `/opt/zig` (with a
symlink at `/usr/local/bin/zig`), libgtk-4-dev, xsltproc,
and generates the bindings as described above. Zig 0.17.0 is
pinned because that is the version the zig-gobject generator
and generated bindings are tested with.

Fedora (not yet tested here — `install_fedora.sh` is the Fedora
equivalent of `install_ubuntu.sh`):

```sh
./install_fedora.sh
./build_linux.sh
./zig-out/bin/zig-gobject
```

## Status

Hello world, open window: done and verified here — the app
opens a 900x600 window titled "Recipe Manager" containing a
"Hello, GTK4!" label, confirmed by screenshot under Xvfb.
Recipe list and detail view, hard-coded data: done and
verified here — a GtkListBox of the same 3 recipes the other
stacks start with (Banana Bread, Tomato Basil Pasta, Chicken
Stir Fry) on the left, detail pane (title, description,
servings, ingredients, numbered steps, notes) on the right,
confirmed by screenshot under Xvfb including a click on the
second row switching the detail to Tomato Basil Pasta.
Recipe view with SQLite integration: done — recipes load
from recipes.db in the current working directory, seeded on
first run with the same 3 recipes (src/db.zig declares the
system SQLite C API by hand, as Zig ships no SQLite package
and Zig 0.17 removed @cImport; the seed data lives in
src/main.zig and is passed to db.ensureLoaded()). The
database file is git-ignored, not pushed.
Add recipe: done — an "Add recipe" button opens a modal
form window (title required, servings spin button, dynamic
ingredient and step rows with Remove buttons); saving
inserts into the database via db.zig, reloads, and selects
the new recipe.

The built `zig-out/` and `third_party/` are git-ignored
and never pushed.

## Tests

None yet.
