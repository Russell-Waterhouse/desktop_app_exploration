#pragma once

// JSON import for the recipe manager: fetch a recipe document
// from a URL, or read one from a local file, and parse it into
// recipes. Both routes share parse_recipes, so the file route
// accepts exactly the same document shapes and field defaults
// as the URL route.
//
// This mirrors rust-egui's json_import.rs in behaviour, with
// one new dependency: ICU, for text-encoding detection and
// conversion (see decode_import_bytes). Fetching is plain POSIX
// sockets (http:// only, no TLS) and parsing is a small
// recursive-descent parser written for exactly the recipe shapes
// below, so this file and json_import.cpp build with plain g++
// plus ICU — no GTK, no SQLite, no JSON library. The unit tests
// (test_json_import.cpp) build that way on purpose, the same
// reason test_search.cpp builds with plain g++.
//
// Accepted document shapes (see test-data/README.md):
//   - a single recipe object: {"title": ..., ...}
//   - a bare array of recipe objects: [{...}, {...}]
//   - a collection object: {"recipes": [...]}
// Per-recipe fields, following test-data/recipes.json: title,
// description, servings, image_path, notes, ingredients (amount,
// unit, name objects, in order), and steps (strings, in order).
// Missing description, notes, ingredients, or steps default to
// empty; missing image_path defaults to null (empty here);
// missing servings defaults to 0. A recipe with no usable title
// (missing, not a string, or blank) is an error, not a recipe
// with an empty title in the list. Unknown fields are ignored.
// Servings must be a JSON integer; a float or a string is an
// error, matching serde's i64 parsing in rust-egui.
//
// HTTPS is rejected with a clear message, exactly as in
// rust-egui: this importer does not do TLS, and the QA route
// for this test app is the local test-data server, which serves
// plain http:// on localhost. Up to 3 redirects are followed.
// Fetch timeouts match rust-egui: 10s to connect, 30s to
// read/write. Chunked transfer encoding is decoded.
//
// ImportedRecipe is deliberately separate from db.h's Recipe:
// the DB layer needs SQLite headers, and keeping this module
// free of them keeps the tests dependency-free. main.cpp
// converts ImportedRecipe to Recipe (clamping servings to int
// range) and inserts it with the existing insert_recipe, the
// same function the Add form uses.

#include <string>
#include <vector>

struct ImportedIngredient {
    std::string amount;
    std::string unit;
    std::string name;
};

struct ImportedRecipe {
    std::string title;
    std::string description;
    long long servings = 0;
    // Empty means no image (stored as NULL in the database).
    std::string image_path;
    std::vector<ImportedIngredient> ingredients;
    std::vector<std::string> steps;
    std::string notes;
};

// Parse a document in any of the accepted shapes. Returns false
// and sets error on any malformed input; nothing is appended to
// out on failure.
bool parse_recipes(const std::string& text,
                   std::vector<ImportedRecipe>& out, std::string& error);

// Fetch a document body over http://. Returns false and sets
// error on DNS/connect/read failure, a non-200 status, too many
// redirects, or an https:// URL.
bool fetch_url(const std::string& url, std::string& body,
               std::string& error);

// Fetch a document and parse it. This is what the worker thread
// runs, so a slow server or a large document never blocks the UI.
bool fetch_and_parse(const std::string& url,
                     std::vector<ImportedRecipe>& out,
                     std::string& error);

// Read a whole file, detect its text encoding, decode it to
// UTF-8, and parse it, exactly as rust-egui's import_from_file
// does. See decode_import_bytes for how the encoding is
// detected, and test-data/encoding_test_data/ for the fixtures
// each encoding is tested against. A file that cannot be read
// is an error of the form "Could not read file {path}: {err}";
// a decode failure reads "Could not read file {path}: <decode
// error>"; a parse failure goes through parse_recipes'
// "Could not parse recipe JSON" path.
bool import_from_file(const std::string& path,
                      std::vector<ImportedRecipe>& out,
                      std::string& error);

// Decodes imported JSON bytes to UTF-8 text, detecting the
// encoding. A byte-order mark wins outright: UTF-8, UTF-16LE,
// or UTF-16BE. Without one, ICU's charset detector guesses from
// the content (verified against the encoding fixtures: it
// distinguishes Windows-1252 from ISO-8859-1, and recognises
// UTF-16LE even without a BOM). The conversion is strict: a
// byte sequence that is not valid in the detected encoding is
// an import error, not garbled text in the list. Empty input
// decodes to empty; the parser then fails downstream, as
// before. On failure returns false and sets error.
bool decode_import_bytes(const std::string& bytes, std::string& text,
                         std::string& error);
