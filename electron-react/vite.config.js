import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Vite builds only the React renderer here, not the Electron
// main process (electron/main.cjs is plain Node and runs as-is).
// root is the renderer source dir, so index.html lives at
// src/renderer/index.html and the build lands in
// dist/renderer/. base './' matters: the main process loads
// the built file with loadFile (a file:// URL), so asset
// paths must be relative, not absolute from a web root.
export default defineConfig({
  plugins: [react()],
  root: 'src/renderer',
  base: './',
  build: {
    outDir: '../../dist/renderer',
    emptyOutDir: true,
  },
})
