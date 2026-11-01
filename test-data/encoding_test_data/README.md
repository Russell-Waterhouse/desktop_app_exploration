# encoding_test_data

Five copies of the same Mushroom Risotto recipe (based on
`../recipe-single.json`, with a few extra non-ASCII characters), each
written in a different byte encoding. For testing text-encoding
detection and import.

| File                      | Encoding                | BOM        | Bytes |
| ------------------------- | ----------------------- | ---------- | ----- |
| `recipe-utf8.json`        | UTF-8                   | none       | 1449  |
| `recipe-utf8-bom.json`    | UTF-8                   | `EF BB BF` | 1452  |
| `recipe-utf16le-bom.json` | UTF-16LE                | `FF FE`    | 2874  |
| `recipe-windows-1252.json`| Windows-1252 (CP1252)   | none       | 1436  |
| `recipe-latin-1.json`     | ISO-8859-1 (Latin-1)    | none       | 1439  |

All five are valid JSON and end with a single LF. The UTF-8, UTF-8-BOM,
UTF-16LE-BOM, and Windows-1252 files decode to exactly the same text.

## Regenerating

`generate_encodings.py` holds the canonical recipe and the per-encoding
writes; the JSON files are generated, not hand-edited. Run it to rewrite
all five fixtures in place:

```
python3 generate_encodings.py
```

The output is deterministic (same recipe text, same JSON formatting, same
trailing LF), so re-running it should leave the files byte-for-byte
unchanged.

## Windows-1252 vs. Latin-1

The recipe contains three characters that exist in Windows-1252 but not
in ISO-8859-1:

| Character | Code point | CP1252 byte | Occurrences |
| --------- | ---------- | ----------- | ----------- |
| `—` em dash                    | U+2014 | `0x97` | 3 |
| `’` right single quotation mark| U+2019 | `0x92` | 1 |
| `€` euro sign                  | U+20AC | `0x80` | 1 |

So Windows-1252 and Latin-1 decoding of this recipe must differ in at
least these places. `recipe-windows-1252.json` contains the real
typographic characters and the raw bytes `0x80`, `0x92`, and `0x97`.
Those bytes are C1 control characters in ISO-8859-1 and are invalid in
UTF-8, so a detector should choose Windows-1252 (not Latin-1) for that
file.

ISO-8859-1 cannot represent those characters at all, so
`recipe-latin-1.json` uses readable ASCII fallbacks in exactly those
spots: `-` for the em dash, `'` for the right single quote, and `EUR `
for the euro sign. Everything else is identical, including `é` in
"Sauté" (`0xE9`), `è` and `î` in "crème fraîche" (`0xE8`, `0xEE`),
which map to the same bytes in both code pages.

Expected text differences between the Windows-1252 and Latin-1 files:

```
…parmesan — a classic…        → …parmesan - a classic…
…at a time — the rice…        → …at a time - the rice…
…don’t crowd the pan…         → …don't crowd the pan…
…evaporated — about 2…        → …evaporated - about 2…
…(about €3 worth)             → …(about EUR 3 worth)
```
