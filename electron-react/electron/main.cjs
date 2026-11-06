// Electron main process (Node, CommonJS).
// Opens one 900x600 window titled "Recipe Manager" and loads
// the React renderer built by Vite into dist/renderer/.
// No preload script yet: the hello-world renderer needs no
// Node access, so contextIsolation stays on and
// nodeIntegration stays off (Electron's secure defaults).
const { app, BrowserWindow } = require('electron')
const path = require('node:path')

function createWindow() {
  const win = new BrowserWindow({
    width: 900,
    height: 600,
    title: 'Recipe Manager',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
    },
  })
  win.loadFile(path.join(__dirname, '..', 'dist', 'renderer', 'index.html'))
}

app.whenReady().then(createWindow)

app.on('window-all-closed', () => {
  // macOS convention is to keep the app alive until Cmd+Q;
  // everywhere else, closing the last window quits.
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow()
  }
})
