# electron-react

Electron + React version of the recipe manager test app.

Electron 45 (Chromium 156, Node 24.22) is the shell; the UI
is React 19, built with Vite 7. The main process
(`electron/main.cjs`, plain Node, CommonJS) opens the window
and loads the built renderer from `dist/renderer/index.html`.
There is no preload script yet: the hello-world renderer
needs no Node access, so contextIsolation stays on and
nodeIntegration stays off, Electron's secure defaults.

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
opens a 900x600 window titled "Recipe Manager" containing a
"Hello, Electron!" heading, confirmed by screenshot under Xvfb.
Recipe list and detail view, hard-coded data: not yet done.

The `node_modules/` and `dist/` directories are git-ignored
and never pushed; `package-lock.json` is pushed, so the
build pins the exact Electron, React, and Vite versions.
