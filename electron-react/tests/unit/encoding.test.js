import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { decodeImportBytes } from '../../src/shared/encoding.js'
import { parseRecipes } from '../../src/shared/jsonRecipes.js'

const FIXTURES = new URL(
  '../../../test-data/encoding_test_data/',
  import.meta.url,
).pathname

function fixture(name) {
  return readFileSync(`${FIXTURES}${name}`)
}

describe('decodeImportBytes against the encoding fixtures', () => {
  it('decodes UTF-8, UTF-8-BOM, UTF-16LE-BOM, and Windows-1252 to the same text', () => {
    const texts = ['recipe-utf8.json', 'recipe-utf8-bom.json', 'recipe-utf16le-bom.json', 'recipe-windows-1252.json'].map(
      (f) => decodeImportBytes(fixture(f)),
    )
    for (const text of texts.slice(1)) {
      expect(text).toBe(texts[0])
    }
    const recipes = parseRecipes(texts[0])
    expect(recipes[0].title).toBe('Mushroom Risotto')
  })

  it('decodes the Windows-1252 typographic characters, not Latin-1 fallbacks', () => {
    const text = decodeImportBytes(fixture('recipe-windows-1252.json'))
    expect(text).toContain('parmesan — a classic')
    expect(text).toContain('don’t crowd the pan')
    expect(text).toContain('about €3 worth')
  })

  it('decodes the Latin-1 fixture with its ASCII fallbacks', () => {
    const text = decodeImportBytes(fixture('recipe-latin-1.json'))
    expect(text).toContain('parmesan - a classic')
    expect(text).toContain("don't crowd the pan")
    expect(text).toContain('about EUR 3 worth')
    expect(text).not.toContain('—')
  })

  it('decodes UTF-16BE with a BOM', () => {
    const utf8 = readFileSync(`${FIXTURES}recipe-utf8.json`, 'utf-8')
    const utf16be = Buffer.alloc(2 + utf8.length * 2)
    utf16be[0] = 0xfe
    utf16be[1] = 0xff
    for (let i = 0; i < utf8.length; i += 1) {
      utf16be.writeUInt16BE(utf8.charCodeAt(i), 2 + i * 2)
    }
    expect(decodeImportBytes(utf16be)).toBe(utf8)
  })

  it('decodes Shift_JIS (no BOM, so the detector must find it)', () => {
    // A Japanese recipe JSON-encoded in Shift_JIS (generated
    // with Python's shift_jis codec; test-data/ has no
    // Shift_JIS fixture, so this stack keeps its own).
    // The bytes are embedded as base64, not as a file:
    // a Shift_JIS file is not valid UTF-8, and the repo's
    // snapshot push only accepts UTF-8 files, so a fixture
    // file could not be pushed. The title and notes must
    // come back as the original Japanese text.
    const bytes = Buffer.from(
      'eyJ0aXRsZSI6ICKWoZFYj2AiLCAiZGVzY3JpcHRpb24iOiAik6SVhYLGgu2CqYLfgsyWoZFYj2CCxYK3gUIiLCAic2VydmluZ3MiOiAyLCAiaW1hZ2VfcGF0aCI6IG51bGwsICJub3RlcyI6ICKJt4KpgqKCpIK/gsmCx4KkgryBQiIsICJpbmdyZWRpZW50cyI6IFt7ImFtb3VudCI6ICIyIiwgInVuaXQiOiAikpoiLCAibmFtZSI6ICKTpJWFIn1dLCAic3RlcHMiOiBbIoK+grWC8Im3gt+C6YFCIiwgIpahkViC8JdugqmCt4FCIl19',
      'base64',
    )
    const recipes = parseRecipes(decodeImportBytes(bytes))
    expect(recipes[0].title).toBe('味噌汁')
    expect(recipes[0].description).toBe('豆腐とわかめの味噌汁です。')
  })

  it('decodes empty input to empty', () => {
    expect(decodeImportBytes(new Uint8Array([]))).toBe('')
  })

  it('decodes a bare BOM to empty', () => {
    expect(decodeImportBytes(new Uint8Array([0xef, 0xbb, 0xbf]))).toBe('')
  })
})
