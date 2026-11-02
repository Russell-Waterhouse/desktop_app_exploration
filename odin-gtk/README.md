# odin-gtk

Odin + GTK4 version of the recipe manager test app, using the
PucklaJ/odin-gtk bindings (generated Odin bindings to GTK4 and
libadwaita, including pango and cairo). This stack stands on the
same Pango text stack as cpp-gtk4, so displayed text shaping
and label selectability come from GTK itself rather than from
code in this app.

## Bindings

The bindings are NOT vendored in this repo: they are a large
generated tree owned by another project, so install_ubuntu.sh
and install_fedora.sh clone them into third_party/odin-gtk,
pinned to tag 4.17.2, and src/main.odin imports them by
relative path, the way the bindings' own examples do. The
bindings link against the system GTK libraries by default
(their GLIB_STATIC option is off unless defined), so the
install scripts install libgtk-4-dev (Ubuntu) / gtk4-devel
(Fedora); no static-library setup is needed on Linux.

Note the pinned version's API idiom, which differs from the
bindings' default branch: windows are built in the activate
handler, signal handlers are passed as cast(gobj.Callback)
with a trailing nil user-data argument, and the application
is run through gobj.type_cast to gio.Application with an
explicit argv. Copying the default-branch example verbatim
against tag 4.17.2 does not compile (its application_run
wrapper and WINDOW cast do not exist in 4.17.2).

## Build

Ubuntu:

```sh
./install_ubuntu.sh
./build_linux.sh
./odin-gtk
```

`install_ubuntu.sh` installs Odin dev-2026-10 to `/opt/odin`
(with a wrapper at `/usr/local/bin/odin` that sets
ODIN_ROOT=/opt/odin), libgtk-4-dev, and the bindings.

Fedora (not yet tested here — `install_fedora.sh` is the Fedora
equivalent of `install_ubuntu.sh`):

```sh
./install_fedora.sh
./build_linux.sh
./odin-gtk
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
first run with the same 3 recipes (src/db.odin declares the
system SQLite C API by hand, as Odin ships no SQLite
package; src/recipes.odin holds the seed data). The database
file is git-ignored, not pushed.
Add recipe: done — an "Add recipe" button opens a modal
form window (title required, servings spin button, dynamic
ingredient and step rows with Remove buttons); saving
inserts into the database via db.odin, reloads, and selects
the new recipe.
Edit recipe: done — an "Edit recipe" button in the
detail pane opens the same form pre-filled with the
selected recipe; saving updates it in place (children
replaced) instead of inserting.
Delete recipe: done — a "Delete recipe" button in the
detail pane opens a confirmation dialog naming the
recipe; confirming deletes it and its children, reloads,
and selects the first remaining recipe (or clears the
detail pane when none remain).
Search: done — a search entry at the top of the left
pane filters the list by title (case-insensitive
substring, empty query shows all, query not trimmed);
the list holds indices into the recipe array so row
selection, add/edit/delete reselection, and the empty
result (cleared detail) all follow the filter.
Upstream notes Linux and Windows support for the bindings;
only Linux has been verified here.

The built `odin-gtk` binary and `third_party/` are git-ignored
and never pushed.

## Tests

None yet.
