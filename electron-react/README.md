# electron-react

Electron + React version of the recipe manager test app.

Electron 45 (Chromium 156, Node 24.22) is the shell; the UI
is React 19, built with Vite 7. The main process
(`electron/main.cjs`, plain Node, CommonJS) opens the window
and loads the built renderer from `dist/renderer/index.html`.
The database layer lives in the main process
(`electron/db.cjs`, Node 24's built-in `node:sqlite` —
verified to work under Electron 45's bundled Node 24.22.2,
so no native SQLite dependency is needed), as do
filesystem work (images, JSON import/export) and network
fetching; the renderer reaches them only through the narrow
`window.recipeAPI` bridge in `electron/preload.cjs`
(contextIsolation on, nodeIntegration off, Electron's
secure defaults).

Pure logic (seed data, search filter, recipe JSON
parse/export, text-encoding detection) lives in
`src/shared/`, as ESM modules importable from both the
main process (Node 24 supports `require()` of ESM) and the
Vitest unit tests, so the tests do not need Electron.

No packaging tool yet (no Electron Forge, no
electron-builder): packaging and distribution are out of
scope for this test, the same as the other stacks. The
build script installs npm dependencies and builds the
renderer; `npm start` runs the app from the build output.

## Build

Ubuntu:

```sh
./install_ubuntu.sh
./build_linux.sh
npm start
```

`install_ubuntu.sh` installs Node.js 24 LTS (from NodeSource
when the installed Node is missing or older than 24;
Ubuntu 24.04's own nodejs package is Node 18, too old for
Electron 45) and the Electron system libraries
(GTK3, NSS, ATK, GBM, ALSA, and the X11 pieces).

Fedora (not yet tested here — `install_fedora.sh` is the Fedora
equivalent of `install_ubuntu.sh`):

```sh
./install_fedora.sh
./build_linux.sh
npm start
```

Running as root (as in a CI container or this VM) needs
`--no-sandbox`, because Electron's sandbox does not support
a root session:

```sh
npx electron . --no-sandbox
```

## Status

Hello world, open window: done and verified here — the app
opens a 900x600 window titled "Recipe Manager", confirmed
by screenshot under Xvfb.
Recipe list and detail view, hard-coded data: done and
verified here — the list/detail UI renders the seed data
(`src/shared/seed.js`, the same 3 starter recipes as the
other stacks) with the detail pane on the right, confirmed
by screenshot under Xvfb.
Recipe view with SQLite integration: done — recipes load
from recipes.db in the current working directory, seeded on
first run with 7 recipes (the original 3 plus the 4
complex-text probes; 7/27/21 recipes/ingredients/steps,
matching the other stacks). The database file is
git-ignored, not pushed.
Add recipe: done — an "Add recipe" button opens a modal
form (title required, servings 1..100, dynamic ingredient
and step rows with Remove buttons); saving inserts into
the database via the main process, reloads, and selects
the new recipe.
Edit recipe: done — an "Edit recipe" button in the detail
pane opens the same form pre-filled with the selected
recipe; saving updates it in place (children replaced)
instead of inserting.
Delete recipe: done — a "Delete recipe" button in the
detail pane opens a confirmation dialog naming the
recipe; confirming deletes it and its children, reloads,
and selects the first remaining recipe.
Search: done — a search entry at the top of the left pane
filters the list by title (case-insensitive substring,
empty query shows all, query not trimmed); the first match
is selected, and a zero-match query clears the detail.
Display images: done — list rows show 32x32 thumbnails
and the detail pane shows the photo at its decoded size
(at most 400x300, never scaled up, via CSS max-width /
max-height); images are read by the main process and
shown as data URLs, with a spinner while loading and a
status line when a load fails.
Import image from file: done — the add/edit form has a
"Choose image…" button (native file dialog); choosing
copies the file into images/ (collision suffix _1, _2
before the extension) and stores the relative path.
Display animations: done — the detail pane fades in
(opacity 0 to 1 over 0.25s, ease-out, via a CSS keyframe
animation re-triggered per selection); image loading shows
a spinner in the detail pane and in list rows while the
main process reads the file.
Network JSON import: done — a URL entry (default
http://localhost:8000/recipes.json) and an "Import from URL"
button fetch with the main process's fetch (redirects
followed), with a spinner and a status line; the app stays
responsive, and success reloads from the database and
selects the first imported recipe. Same shapes as the
other stacks: bare object, {"recipes": [...]}, and array.
Raw-file import: done — "Import from file…" opens a native
file dialog; single and collection shapes; errors surface
as a red status line.
Raw-file export: done — "Export recipe…" (initial name
<title>.json, bare object) and "Export all…" (initial name
recipes.json, {"recipes": [...]}) open native save dialogs.
Text-encoding import: done — BOM sniff, then strict UTF-8
first, then `chardet` detection (pure JS, no native code)
and strict TextDecoder conversion (fatal:true, so an
undecodable byte is an error, never U+FFFD), for both file
and URL imports; decode errors are import errors, never
substituted text. `chardet` was verified against all five
fixtures in test-data/encoding_test_data/ and a realistic
Shift_JIS document. The error message matches the other
stacks: "Imported text could not be decoded as {name}."
Complex text: done — the four probe recipes (Arabic,
Devanagari, Simplified Chinese, emoji) are seed data and
render correctly via Chromium with zero font configuration;
detail text is selectable, so drag-select and Ctrl+C copy
work (verified by the UI tests driving the real app);
list-row titles stay unselectable so row clicks select the
recipe, the same trade-off as cpp-gtk4.
Text input: done — description and notes are multiline
textareas; Chromium gives the form fields native text
editing, so multiline editing, drag-select, Ctrl+C/Ctrl+V,
Ctrl+Z undo, and Ctrl+Shift+Z / Ctrl+Y redo all work with
no custom undo code (unlike the GTK stacks, whose entries
and text views have no built-in undo). Empty title shows
"Title is required." All verified in the real app by the
UI tests.

The `node_modules/` and `dist/` directories are git-ignored
and never pushed; `package-lock.json` is pushed, so the
build pins the exact Electron, React, Vite, and chardet
versions. `recipes.db` and `images/` are git-ignored too.

## Performance

Measured with `./profile_performance_linux.sh` (10s idle under
Xvfb in a fresh temp directory, same workload as the other
stacks), 2026-11-06 05:31:47:

- compile: clean 2.410s, cached 2.426s (`npm run build`,
  vite build of the renderer; Vite rebuilds the whole bundle
  either way, so the two are close, like Odin)
- binary size: 287,488,971 bytes — the runnable app
  (Electron runtime + main process + built renderer); the
  runtime dominates, as expected for Electron
- memory (whole Electron process tree, 6 processes): peak
  240,507 kB PSS, average 239,730 kB
- CPU (whole tree): peak 2.17%, average 0.31%

Electron has no debug/release build split, so the debug and
release columns in `performance_metrics.csv` carry the same
measured values; see the header of
`profile_performance_linux.sh` for the full mapping. The
combined file at the repo root
(`performance_metrics_all.csv`) includes this stack's row.

## Tests

Unit tests (`npm test`, Vitest, 42 tests, all passing):
recipe data and seed counts, search, JSON import/export
(including the encoding fixtures, which read test-data/
from the repo root, plus a Shift_JIS case whose bytes are
embedded as base64 in the test — a Shift_JIS file is not
valid UTF-8, and the repo's snapshot push only accepts
UTF-8 files, so it cannot live as a fixture file),
SQLite insert/update/delete/seed, and image
copy/collision/read.

UI tests (`npm run test:ui`, Playwright Electron, 13 tests,
all passing): list click shows detail, search filters list,
search with no match clears detail, add via form, add
rejects empty title, edit changes title, delete removes
it, complex-text input in Arabic/Devanagari/Simplified
Chinese/emoji, text input undo/redo, import from URL,
import from file, export all, choose image. Each test
launches the real built app in its own temporary working
directory with a fresh recipes.db. The URL-import test
needs the test-data server running (test-data/run_server.sh);
the file import/export/image tests stub Electron's native
dialogs to fixed paths, because Playwright cannot drive a
native OS file dialog.
