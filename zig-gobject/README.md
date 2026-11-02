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
src/recipes.zig and is passed to db.ensureLoaded()). The
database file is git-ignored, not pushed.
Add recipe: done — an "Add recipe" button opens a modal
form window (title required, servings spin button, dynamic
ingredient and step rows with Remove buttons); saving
inserts into the database via db.zig, reloads, and selects
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
Display images: done — list rows show 32x32 thumbnails and
the detail pane shows the photo at its decoded size (at most
400x300, never scaled up: GtkPicture content-fit SCALE_DOWN);
decoding happens on a worker thread via
gdkpixbuf.Pixbuf.newFromFile plus scaleSimple, rows show a
spinner while loading, and a failed load shows a status line
and is not retried.
Import image from file: done — the add/edit form has a
"Choose image…" button (GtkFileDialog); choosing copies the
file into images/ (collision suffix _1, _2 before the
extension) and stores the relative path.
Display animations: done — the detail pane fades in (opacity
0 to 1 over 0.25s, ease-out cubic, driven by a 16ms glib
timeout) on selection change; image loading shows a spinner
in the detail pane and in list rows while the worker decodes.
The fade itself is implemented, not screenshot-verified: it
is too fast for screenshot roundtrips.
Network JSON import: done — a URL entry (default
http://localhost:8000/recipes.json) and an "Import from URL"
button fetch on a worker thread, with a spinner and a status
line; the app stays responsive, and success reloads from the
database and selects the first imported recipe. Same shapes
as the other stacks: bare object, {"recipes": [...]}, and
array. Caveat, same as zig-dvui: the HTTP client is raw
Linux syscalls, because std.Io.net reads hang on worker
threads — so this is Linux-only (documented in
src/json_import.zig).
Raw-file import: done — "Import from file…" opens a
GtkFileDialog; single and collection shapes; errors surface
as a red status line. A dismissed dialog (Cancel, window
close, Escape) is silent: GtkFileDialog reports that as
GTK_DIALOG_ERROR_DISMISSED, not G_IO_ERROR_CANCELLED.
Raw-file export: done — "Export recipe…" (initial name
<title>.json, bare object) and "Export all…" (initial name
recipes.json, {"recipes": [...]}) open save dialogs.
Text-encoding import: done — BOM sniff, then ICU detection
(ucsdet) and strict conversion (ucnv with the STOP
callback), for both file and URL imports; decode errors are
import errors, never substituted text. The ICU API comes
from a build-time translate-c of src/icu.h (see the ICU
section below); libicu-dev / libicu-devel were added to the
install scripts.
Complex text: done — the four probe recipes (Arabic,
Devanagari, Simplified Chinese, emoji) are seed data and
render correctly via Pango with zero font configuration;
detail labels are selectable, so drag-select and Ctrl+C copy
work (verified by pasting a selection into the search entry);
list-row titles stay unselectable so row clicks select the
recipe, the same trade-off as cpp-gtk4.
Text input: done — description and notes moved from
single-line entries to wrapped GtkTextViews (Tab moves
focus, it does not insert a tab), so multiline editing
works; GTK4's entries and text views have no built-in undo,
so the form implements it with one pure-logic TextUndo
(src/text_undo.zig, unit-tested) per text widget, driven
by a key controller on the form window: Ctrl+Z undoes,
Ctrl+Shift+Z and Ctrl+Y redo, in whichever text widget has
focus, with typing runs under a second coalesced into one
step. The clock is injected (the app passes glib monotonic
time; Zig 0.17's std has no timestamp helper), which also
makes the coalescing tests deterministic. The servings spin
button is left out on purpose: its input is already
constrained to whole numbers. Fixed along the way: openForm
never assigned form.image_path for a new recipe, and
create() does not apply the struct's = "" default, so
saving a recipe without an image could crash in
bindImagePath on a garbage-length string; it is now set
explicitly.

The built `zig-out/` and `third_party/` are git-ignored
and never pushed.

## Tests

`zig build test` — 70 tests, all passing: seed counts
(7 recipes / 27 ingredients / 21 steps), search, database
seed/insert/update/delete round-trip, image copy/collision,
JSON import (including the encoding fixtures and a one-shot
local server; the URL tests need the test-data server on
localhost:8000), JSON export, and text undo/redo.
