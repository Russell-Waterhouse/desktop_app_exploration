// Recipe image files on disk, mirroring odin-gtk's
// images.odin: choosing an image copies the file into
// images/ (collision suffix _1, _2 before the extension)
// and stores the relative path ("images/<name>") in the
// database. Display reads the file back as a data URL:
// the renderer cannot read the filesystem itself
// (contextIsolation on, nodeIntegration off), and a data
// URL needs no file-access flags in the renderer.

const fs = require('node:fs')
const path = require('node:path')

const MIME_BY_EXT = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml',
}

// Copy a file into images/ under the working directory.
// On a name collision, appends _1, _2 before the extension.
// Returns the relative path ("images/<name>") to store.
function copyImageFile(sourcePath, cwd) {
  const imagesDir = path.join(cwd, 'images')
  fs.mkdirSync(imagesDir, { recursive: true })
  const ext = path.extname(sourcePath)
  const base = path.basename(sourcePath, ext)
  let name = path.basename(sourcePath)
  let n = 0
  while (fs.existsSync(path.join(imagesDir, name))) {
    n += 1
    name = `${base}_${n}${ext}`
  }
  fs.copyFileSync(sourcePath, path.join(imagesDir, name))
  return `images/${name}`
}

// Read an image (relative path, e.g. "images/foo.png") and
// return { ok: true, dataUrl } or { ok: false, error }.
function readImageDataUrl(relPath, cwd) {
  const full = path.join(cwd, relPath)
  try {
    const data = fs.readFileSync(full)
    const mime = MIME_BY_EXT[path.extname(full).toLowerCase()] ?? 'application/octet-stream'
    return { ok: true, dataUrl: `data:${mime};base64,${data.toString('base64')}` }
  } catch (e) {
    return { ok: false, error: `Could not load image ${relPath}: ${e.message}` }
  }
}

module.exports = { copyImageFile, readImageDataUrl }
