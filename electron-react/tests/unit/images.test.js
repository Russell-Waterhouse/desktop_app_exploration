import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { copyImageFile, readImageDataUrl } from '../../electron/images.cjs'

let dir

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'electron-react-images-test-'))
})

afterEach(() => {
  rmSync(dir, { recursive: true, force: true })
})

// A 1x1 transparent PNG, base64.
const PNG_1X1 = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
)

describe('copyImageFile', () => {
  it('copies into images/ and returns the relative path', () => {
    const source = join(dir, 'photo.png')
    writeFileSync(source, PNG_1X1)
    expect(copyImageFile(source, dir)).toBe('images/photo.png')
    expect(existsSync(join(dir, 'images', 'photo.png'))).toBe(true)
  })

  it('adds _1, _2 collision suffixes before the extension', () => {
    const source = join(dir, 'photo.png')
    writeFileSync(source, PNG_1X1)
    expect(copyImageFile(source, dir)).toBe('images/photo.png')
    expect(copyImageFile(source, dir)).toBe('images/photo_1.png')
    expect(copyImageFile(source, dir)).toBe('images/photo_2.png')
  })
})

describe('readImageDataUrl', () => {
  it('reads a copied image back as a data URL', () => {
    const source = join(dir, 'photo.png')
    writeFileSync(source, PNG_1X1)
    const rel = copyImageFile(source, dir)
    const result = readImageDataUrl(rel, dir)
    expect(result.ok).toBe(true)
    expect(result.dataUrl.startsWith('data:image/png;base64,')).toBe(true)
    expect(Buffer.from(result.dataUrl.split(',')[1], 'base64')).toEqual(PNG_1X1)
  })

  it('reports a missing image as an error, not a throw', () => {
    const result = readImageDataUrl('images/nope.png', dir)
    expect(result.ok).toBe(false)
    expect(result.error).toContain('images/nope.png')
  })
})

describe('fixture PNG', () => {
  it('starts with the PNG magic bytes', () => {
    expect(Array.from(PNG_1X1.subarray(0, 8))).toEqual([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ])
  })
})
