// Electron main process (Node, CommonJS).
// Opens one 900x600 window titled "Recipe Manager" and loads
// the React renderer built by Vite into dist/renderer/.
// The database layer lives here (electron/db.cjs, built-in
// node:sqlite), as do filesystem work (images/, JSON
// import/export) and network fetching; the renderer reaches
// them only through the narrow window.recipeAPI bridge in
// electron/preload.cjs (contextIsolation on, nodeIntegration
// off — Electron's secure defaults, unchanged from hello
// world).
//
// The shared pure modules (src/shared/) are ESM; Node 24
// supports require() of ESM, so the main process loads them
// with require() like any other module.

const { app, BrowserWindow, dialog, ipcMain } = require('electron')
const path = require('node:path')
const fs = require('node:fs')

const db = require('./db.cjs')
const images = require('./images.cjs')
const { SEED_RECIPES } = require('../src/shared/seed.js')
const { parseRecipes, exportSingle, exportCollection, defaultFileName } = require('../src/shared/jsonRecipes.js')
const { decodeImportBytes } = require('../src/shared/encoding.js')

const DB_PATH = path.join(process.cwd(), 'recipes.db')
const DEFAULT_IMPORT_URL = 'http://localhost:8000/recipes.json'

let database = null
let dbError = ''

function createWindow() {
  const win = new BrowserWindow({
    width: 900,
    height: 600,
    title: 'Recipe Manager',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.cjs'),
    },
  })
  win.loadFile(path.join(__dirname, '..', 'dist', 'renderer', 'index.html'))
  return win
}

// Insert parsed recipes into the database. Returns
// { imported, firstId, message } or { error }. A failed
// insert stops the import, leaving any recipes already
// inserted in place (like the other stacks).
function insertImported(recipes) {
  let firstId = -1
  let inserted = 0
  for (const recipe of recipes) {
    try {
      const id = db.insertRecipe(database, recipe)
      if (firstId < 0) {
        firstId = id
      }
      inserted += 1
    } catch (e) {
      return { error: e.message }
    }
  }
  const message =
    inserted === 1 ? 'Imported 1 recipe.' : `Imported ${inserted} recipes.`
  return { imported: inserted, firstId, message }
}

async function fetchAndParse(url) {
  let response
  try {
    response = await fetch(url, {
      headers: { Accept: 'application/json', 'User-Agent': 'recipe-manager-test' },
    })
  } catch (e) {
    throw new Error(`Could not connect to ${url}: ${e.message}.`)
  }
  if (!response.ok) {
    throw new Error(`Server returned HTTP ${response.status} for ${url}.`)
  }
  const bytes = new Uint8Array(await response.arrayBuffer())
  const text = decodeImportBytes(bytes)
  return parseRecipes(text)
}

function registerIpc() {
  ipcMain.handle('recipes:list', () => {
    if (dbError) {
      return { error: dbError }
    }
    try {
      return { recipes: db.loadRecipes(database) }
    } catch (e) {
      return { error: e.message }
    }
  })

  ipcMain.handle('recipes:add', (_event, recipe) => {
    try {
      const id = db.insertRecipe(database, recipe)
      return { id }
    } catch (e) {
      return { error: e.message }
    }
  })

  ipcMain.handle('recipes:update', (_event, recipe) => {
    try {
      db.updateRecipe(database, recipe)
      return { ok: true }
    } catch (e) {
      return { error: e.message }
    }
  })

  ipcMain.handle('recipes:delete', (_event, id) => {
    try {
      db.deleteRecipe(database, id)
      return { ok: true }
    } catch (e) {
      return { error: e.message }
    }
  })

  ipcMain.handle('recipes:import-url', async (_event, url) => {
    try {
      const recipes = await fetchAndParse(url)
      return insertImported(recipes)
    } catch (e) {
      return { error: e.message }
    }
  })

  ipcMain.handle('recipes:import-file', async (event) => {
    const win = BrowserWindow.fromWebContents(event.sender)
    const picked = await dialog.showOpenDialog(win, {
      title: 'Import recipes from JSON',
      properties: ['openFile'],
      filters: [{ name: 'JSON', extensions: ['json'] }],
    })
    if (picked.canceled || picked.filePaths.length === 0) {
      return { cancelled: true }
    }
    const filePath = picked.filePaths[0]
    try {
      const data = fs.readFileSync(filePath)
      const text = decodeImportBytes(new Uint8Array(data))
      const recipes = parseRecipes(text)
      return insertImported(recipes)
    } catch (e) {
      return { error: `Could not read file ${filePath}: ${e.message}` }
    }
  })

  ipcMain.handle('recipes:export-single', async (event, id) => {
    const win = BrowserWindow.fromWebContents(event.sender)
    let recipe
    try {
      recipe = db.loadRecipes(database).find((r) => r.id === id)
    } catch (e) {
      return { error: e.message }
    }
    if (!recipe) {
      return { error: 'No recipe selected.' }
    }
    const picked = await dialog.showSaveDialog(win, {
      title: 'Export recipe as JSON',
      defaultPath: defaultFileName(recipe.title),
      filters: [{ name: 'JSON', extensions: ['json'] }],
    })
    if (picked.canceled || !picked.filePath) {
      return { cancelled: true }
    }
    try {
      fs.writeFileSync(picked.filePath, exportSingle(recipe))
      return { message: `Exported 1 recipe to ${picked.filePath}.` }
    } catch (e) {
      return { error: `Could not write file ${picked.filePath}: ${e.message}.` }
    }
  })

  ipcMain.handle('recipes:export-all', async (event) => {
    const win = BrowserWindow.fromWebContents(event.sender)
    const picked = await dialog.showSaveDialog(win, {
      title: 'Export all recipes as JSON',
      defaultPath: 'recipes.json',
      filters: [{ name: 'JSON', extensions: ['json'] }],
    })
    if (picked.canceled || !picked.filePath) {
      return { cancelled: true }
    }
    try {
      const recipes = db.loadRecipes(database)
      fs.writeFileSync(picked.filePath, exportCollection(recipes))
      return { message: `Exported all recipes to ${picked.filePath}.` }
    } catch (e) {
      return { error: `Could not write file ${picked.filePath}: ${e.message}.` }
    }
  })

  ipcMain.handle('recipes:choose-image', async (event) => {
    const win = BrowserWindow.fromWebContents(event.sender)
    const picked = await dialog.showOpenDialog(win, {
      title: 'Choose image',
      properties: ['openFile'],
      filters: [
        {
          name: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
        },
      ],
    })
    if (picked.canceled || picked.filePaths.length === 0) {
      return { cancelled: true }
    }
    try {
      const relPath = images.copyImageFile(picked.filePaths[0], process.cwd())
      return { relPath }
    } catch (e) {
      return { error: e.message }
    }
  })

  ipcMain.handle('recipes:read-image', (_event, relPath) => {
    return images.readImageDataUrl(relPath, process.cwd())
  })
}

app.whenReady().then(() => {
  try {
    database = db.openDatabase(DB_PATH)
    db.ensureSchemaAndSeed(database, SEED_RECIPES)
  } catch (e) {
    dbError = e.message
  }
  registerIpc()
  createWindow()
})

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

app.on('before-quit', () => {
  db.closeDatabase(database)
  database = null
})
