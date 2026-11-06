// Preload script: the only bridge between the renderer and
// the main process. contextIsolation stays on and
// nodeIntegration stays off; the renderer gets a narrow,
// named API on window.recipeAPI and nothing else — no Node
// globals, no direct filesystem or SQLite access.

const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('recipeAPI', {
  list: () => ipcRenderer.invoke('recipes:list'),
  add: (recipe) => ipcRenderer.invoke('recipes:add', recipe),
  update: (recipe) => ipcRenderer.invoke('recipes:update', recipe),
  delete: (id) => ipcRenderer.invoke('recipes:delete', id),
  importUrl: (url) => ipcRenderer.invoke('recipes:import-url', url),
  importFile: () => ipcRenderer.invoke('recipes:import-file'),
  exportSingle: (id) => ipcRenderer.invoke('recipes:export-single', id),
  exportAll: () => ipcRenderer.invoke('recipes:export-all'),
  chooseImage: () => ipcRenderer.invoke('recipes:choose-image'),
  readImage: (relPath) => ipcRenderer.invoke('recipes:read-image', relPath),
})
