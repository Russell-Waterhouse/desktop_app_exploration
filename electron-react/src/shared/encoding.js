// Text-encoding import, mirroring odin-gtk/src/json_import.odin
// (which uses ICU): import bytes are decoded to UTF-8 before
// parsing, so file and URL imports accept UTF-8 (with or
// without BOM), UTF-16LE/BE (with BOM), Windows-1252, and
// Shift_JIS, and store equivalent UTF-8 in SQLite.
//
// Detection runs only when there is no BOM: BOM sniffing
// precedes heuristic detection, because a detector alone
// misreads BOM'd UTF-16LE as windows-1252 (seen with
// chardetng in the Rust round; the rule is the same here).
//
// The detector is the `chardet` npm package (pure JS, no
// native code): it was verified against all five fixtures in
// test-data/encoding_test_data/ (UTF-8, UTF-8-BOM,
// UTF-16LE-BOM, Windows-1252, Latin-1 — all detected
// correctly) and against a realistic Shift_JIS document
// (detected as Shift_JIS, decoded correctly). Conversion is
// Node's built-in TextDecoder with fatal:true, so any
// undecodable byte is an error, never a U+FFFD substitution
// — the same strict rule as the other stacks, with the same
// error message ("Imported text could not be decoded as
// {name}.").
//
// A shortcut before detection: bytes that decode as strict
// UTF-8 are UTF-8. That keeps plain UTF-8 (the common case)
// off the detector entirely, and matches what the detector
// would say for those files anyway.

import chardet from 'chardet'

const DETECTED_TO_DECODER = {
  'UTF-8': 'utf-8',
  'UTF-16LE': 'utf-16le',
  'UTF-16BE': 'utf-16be',
  'windows-1252': 'windows-1252',
  'ISO-8859-1': 'windows-1252',
  'Shift_JIS': 'shift_jis',
  'Shift-JIS': 'shift_jis',
}

function strictDecode(bytes, name) {
  let decoder
  try {
    decoder = new TextDecoder(name, { fatal: true })
  } catch {
    throw new Error(`Imported text could not be decoded as ${name}.`)
  }
  try {
    return decoder.decode(bytes)
  } catch {
    throw new Error(`Imported text could not be decoded as ${name}.`)
  }
}

// Decode import bytes to UTF-8. Accepts a Uint8Array (or
// Buffer) and returns a string. Throws an Error on
// undecodable input.
export function decodeImportBytes(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input)
  if (bytes.length === 0) {
    return ''
  }
  let name = ''
  let rest = bytes
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    name = 'UTF-8'
    rest = bytes.subarray(3)
  } else if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    name = 'UTF-16LE'
    rest = bytes.subarray(2)
  } else if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    name = 'UTF-16BE'
    rest = bytes.subarray(2)
  }
  if (rest.length === 0) {
    return ''
  }
  if (name !== '') {
    return strictDecode(rest, DETECTED_TO_DECODER[name])
  }
  // No BOM: valid strict UTF-8 is UTF-8.
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(rest)
  } catch {
    // Not UTF-8: ask the detector.
  }
  const detected = chardet.detect(Buffer.from(rest))
  const decoderName = DETECTED_TO_DECODER[detected]
  if (decoderName) {
    return strictDecode(rest, decoderName)
  }
  // Unknown detection result: fall back to strict UTF-8, so
  // the failure surfaces as a decode error, not garbled text.
  return strictDecode(rest, 'utf-8')
}
