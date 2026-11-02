package main

import "core:bytes"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:thread"

// Network JSON import from a URL, and raw-file JSON import
// from a path, matching rust-egui's json_import.rs behaviour
// (see that file for the reference implementation this
// mirrors, including its error strings). The file importer
// reads with import_from_file below and parses with the same
// parse_recipes the URL importer uses, so the shapes and
// defaults are identical; only the source differs.
//
// Accepted document shapes:
//   - a single recipe object: {"title": ..., ...}
//   - a bare array of recipe objects: [{...}, {...}]
//   - a collection object: {"recipes": [...]}
// A recipe's fields follow test-data/recipes.json: title,
// description, servings, image_path, notes, ingredients (amount,
// unit, name objects, in order), and steps (strings, in order).
// Missing description, notes, ingredients, or steps default to
// empty; missing image_path defaults to null ("" here, which
// db.odin inserts as NULL); missing servings defaults to 0.
// A recipe with no usable title is an error, not a recipe with
// an empty title in the list.
//
// FETCHING: plain TCP HTTP with core:net, http:// only, no
// TLS — the QA route for this test app
// is the local test-data server, which serves plain http:// on
// localhost, and this importer says so rather than pretending
// to support https://. Up to 3 redirects are followed, and
// chunked bodies are decoded, like the Rust version.
// Decoding to UTF-8 uses the system ICU library (see the
// text-encoding section below); that is the one non-core
// dependency in this file.
//
// THREADING: the fetch and parse run on a worker thread (see
// Import_Job): the main thread polls with thread.is_done
// from a glib timeout, joins, and only then inserts into
// SQLite with the same insert_recipe the Add form uses.
// The worker touches no GTK state. Every string it builds
// uses context.allocator (the heap allocator on both threads),
// never the main thread's temp allocator — freed every frame
// — which is why this file never uses fmt.tprintf: tprintf
// allocates on the temp allocator, so all error strings here
// are built with fmt.aprintf or strings.concatenate instead.
// The one exception is core:net's own temp-allocator use for
// DNS scratch, which the worker keeps off the shared temp
// allocator by giving itself a private arena (see
// import_job_proc).
//
// OWNERSHIP: parse_recipes clones every string it keeps into
// the given allocator, and destroys the parsed JSON tree, so
// the returned recipes own their strings. After the main
// thread inserts them, it frees the ones it did not keep (see
// poll_import_job): insert_recipe has already stepped the
// statement by then, so the database holds its own copy.

PARSE_ERROR :: "Could not parse recipe JSON: "
SHAPE_ERROR :: "JSON must be a single recipe, an array of recipes, or an object with a \"recipes\" array."

// --- Parsing ---------------------------------------------------------

// A field's string, always cloned into the allocator — even
// when the field is absent, where the clone is empty — so
// every string in a returned Recipe is owned the same way and
// free_recipe_strings can free them uniformly. (A zero-value
// "" is a string literal, not allocator memory, so freeing it
// would be wrong; free_recipe_strings therefore only frees
// non-empty strings, and a cloned empty string costs nothing
// to leave.) A JSON null counts as present but empty, like an
// absent field: image_path null stays "" (which db.odin
// inserts as NULL), while a null title is still "no usable
// title" because the caller checks the trimmed value.
json_string_field :: proc(obj: json.Object, name: string, allocator := context.allocator) -> (string, bool, string) {
	raw, ok := obj[name]
	if !ok {
		return strings.clone("", allocator), false, ""
	}
	if _, is_null := raw.(json.Null); is_null {
		return strings.clone("", allocator), true, ""
	}
	s, is_str := raw.(json.String)
	if !is_str {
		return strings.clone("", allocator), true, fmt.aprintf("%s%s has the wrong type.", PARSE_ERROR, name)
	}
	return strings.clone(string(s), allocator), true, ""
}

parse_recipe_object :: proc(obj: json.Object, allocator := context.allocator) -> (Recipe, string) {
	title, present, err := json_string_field(obj, "title", allocator)
	if err != "" {
		return {}, err
	}
	if !present || strings.trim_space(title) == "" {
		delete(title, allocator)
		return {}, "Imported recipe is missing a title."
	}
	recipe := Recipe{title = title}
	// From here on, every error path frees the partial recipe:
	// each field is assigned into recipe as soon as it is
	// built, so free_recipe_strings covers exactly what exists.
	fail := proc(recipe: ^Recipe, allocator: mem.Allocator, err: string) -> (Recipe, string) {
		free_recipe_strings(recipe^, allocator)
		return {}, err
	}

	description, _, desc_err := json_string_field(obj, "description", allocator)
	if desc_err != "" {
		return fail(&recipe, allocator, desc_err)
	}
	recipe.description = description

	if raw, ok := obj["servings"]; ok {
		servings, is_int := raw.(json.Integer)
		if !is_int {
			return fail(&recipe, allocator, fmt.aprintf("%sservings has the wrong type.", PARSE_ERROR))
		}
		recipe.servings = int(servings)
	}

	image_path, _, img_err := json_string_field(obj, "image_path", allocator)
	if img_err != "" {
		return fail(&recipe, allocator, img_err)
	}
	recipe.image_path = image_path

	notes, _, notes_err := json_string_field(obj, "notes", allocator)
	if notes_err != "" {
		return fail(&recipe, allocator, notes_err)
	}
	recipe.notes = notes

	ingredients := make([dynamic]Ingredient, 0, allocator)
	recipe.ingredients = ingredients[:]
	if raw, ok := obj["ingredients"]; ok {
		list, is_array := raw.(json.Array)
		if !is_array {
			return fail(&recipe, allocator, fmt.aprintf("%singredients has the wrong type.", PARSE_ERROR))
		}
		for item in list {
			ing_obj, is_obj := item.(json.Object)
			if !is_obj {
				return fail(&recipe, allocator, fmt.aprintf("%singredients must be objects.", PARSE_ERROR))
			}
			amount, _, amt_err := json_string_field(ing_obj, "amount", allocator)
			if amt_err != "" {
				return fail(&recipe, allocator, amt_err)
			}
			unit, _, unit_err := json_string_field(ing_obj, "unit", allocator)
			if unit_err != "" {
				delete(amount, allocator)
				return fail(&recipe, allocator, unit_err)
			}
			name, _, name_err := json_string_field(ing_obj, "name", allocator)
			if name_err != "" {
				delete(amount, allocator)
				delete(unit, allocator)
				return fail(&recipe, allocator, name_err)
			}
			append(&ingredients, Ingredient{amount = amount, unit = unit, name = name})
		}
		recipe.ingredients = ingredients[:]
	}

	steps := make([dynamic]string, 0, allocator)
	recipe.steps = steps[:]
	if raw, ok := obj["steps"]; ok {
		list, is_array := raw.(json.Array)
		if !is_array {
			return fail(&recipe, allocator, fmt.aprintf("%ssteps has the wrong type.", PARSE_ERROR))
		}
		for item in list {
			step, is_str := item.(json.String)
			if !is_str {
				return fail(&recipe, allocator, fmt.aprintf("%ssteps must be strings.", PARSE_ERROR))
			}
			append(&steps, strings.clone(string(step), allocator))
		}
		recipe.steps = steps[:]
	}
	return recipe, ""
}

parse_recipe_value :: proc(value: json.Value, allocator := context.allocator) -> (Recipe, string) {
	obj, is_obj := value.(json.Object)
	if !is_obj {
		return {}, fmt.aprintf("%srecipe must be an object.", PARSE_ERROR)
	}
	return parse_recipe_object(obj, allocator)
}

// Parse a whole document in any of the three accepted shapes.
// The returned recipes own their strings (see the file header);
// free them with free_imported_recipes when done. Strict JSON
// (not the package's JSON5 default) and integer numbers, so
// this matches serde_json's behaviour for the fixtures: a
// servings of 4 parses as an integer, and JSON5-only syntax
// is rejected like the Rust version rejects it.
parse_recipes :: proc(text: string, allocator := context.allocator) -> ([]Recipe, string) {
	value, err := json.parse_string(text, .JSON, true, allocator)
	if err != .None {
		return nil, fmt.aprintf("%s%v.", PARSE_ERROR, err)
	}
	defer json.destroy_value(value, allocator)

	switch v in value {
	case json.Array:
		recipes := make([dynamic]Recipe, 0, len(v), allocator)
		for item in v {
			recipe, perr := parse_recipe_value(item, allocator)
			if perr != "" {
				free_imported_recipes(recipes[:], allocator)
				return nil, perr
			}
			append(&recipes, recipe)
		}
		return recipes[:], ""
	case json.Object:
		if raw, ok := v["recipes"]; ok {
			list, is_array := raw.(json.Array)
			if !is_array {
				return nil, "The \"recipes\" field must be an array of recipes."
			}
			recipes := make([dynamic]Recipe, 0, len(list), allocator)
			for item in list {
				recipe, perr := parse_recipe_value(item, allocator)
				if perr != "" {
					free_imported_recipes(recipes[:], allocator)
					return nil, perr
				}
				append(&recipes, recipe)
			}
			return recipes[:], ""
		}
		if _, ok := v["title"]; ok {
			recipe, perr := parse_recipe_object(v, allocator)
			if perr != "" {
				return nil, perr
			}
			recipes := make([dynamic]Recipe, 0, 1, allocator)
			append(&recipes, recipe)
			return recipes[:], ""
		}
		return nil, SHAPE_ERROR
	// json.Value's other members (Integer is i64, Float is
	// f64, Boolean is bool, String is string — plain aliases
	// in this Odin version, not distinct types).
	case json.Null, i64, f64, bool, string:
		return nil, SHAPE_ERROR
	}
	// Unreachable: the switch above covers every Value member,
	// but the compiler cannot prove it, so a trailing return
	// is required.
	return nil, SHAPE_ERROR
}

// Free one parsed recipe's strings and child arrays. Used for
// the uninserted tail in poll_import_job and by tests. Only
// non-empty strings are freed: a field never assigned is the
// "" literal, not allocator memory, and freeing a literal
// would be wrong; a cloned empty string costs nothing to
// leave. Slices are safe to delete even when nil.
free_recipe_strings :: proc(recipe: Recipe, allocator := context.allocator) {
	free_str := proc(s: string, allocator: mem.Allocator) {
		if len(s) > 0 {
			delete(s, allocator)
		}
	}
	free_str(recipe.title, allocator)
	free_str(recipe.description, allocator)
	free_str(recipe.image_path, allocator)
	free_str(recipe.notes, allocator)
	for ingredient in recipe.ingredients {
		free_str(ingredient.amount, allocator)
		free_str(ingredient.unit, allocator)
		free_str(ingredient.name, allocator)
	}
	delete(recipe.ingredients, allocator)
	for step in recipe.steps {
		free_str(step, allocator)
	}
	delete(recipe.steps, allocator)
}

free_imported_recipes :: proc(recipes: []Recipe, allocator := context.allocator) {
	for recipe in recipes {
		free_recipe_strings(recipe, allocator)
	}
	delete(recipes, allocator)
}

// --- Text-encoding import (ICU via foreign import) ------------------
//
// Import bytes are decoded to UTF-8 before parsing, so file
// and URL imports accept UTF-8 (with or without BOM),
// UTF-16LE/BE (with BOM), Windows-1252, and Shift_JIS, and
// store equivalent UTF-8 in SQLite — the same todo item the
// Rust and C++ stacks already implement, with the same error
// message ("Imported text could not be decoded as {name}.").
// Detection runs only when there is no BOM: BOM sniffing
// precedes heuristic detection, because a detector alone
// misreads BOM'd UTF-16LE as windows-1252 (seen with
// chardetng in the Rust round; the rule is the same here).
//
// ICU is reached through Odin's foreign system, the same
// mechanism this package already uses for SQLite (see
// src/db.odin): a foreign import for the system library and
// a foreign block for the procedures. No code generation, no
// headers — the declarations below are the whole binding.
// Gotchas, all verified against the system ICU (74.2) while
// writing this:
// - ICU exports versioned symbols only (ucnv_open_74,
//   ucsdet_open_74, ...), so every foreign proc carries
//   @(link_name="..._74"). The suffix is ICU's major
//   version: it must be updated if the system ICU major
//   changes (Fedora ships a different major than Ubuntu).
// - UErrorCode is a plain c.int, and U_SUCCESS/U_FAILURE are
//   C macros with no symbol to link: success is code <= 0.
// - Plain ucnv_convert silently substitutes U+FFFD for
//   undecodable bytes, so it is never used. The STOP
//   callback below makes undecodable input an error.
//   UCNV_TO_U_CALLBACK_STOP is a real exported function,
//   not a macro, so it is declared as a proc and passed
//   as a proc value.
// - Detector names are ICU-owned and die with the detector:
//   decode_import_bytes clones the name before it can be
//   returned in an error, and frees the clone.
// - ICU lengths are int32: inputs over 2 GB are refused
//   with a decode error instead of truncating the cast.
// - Each decode creates its own detector and converter.
//   ICU objects are not shared across the import worker
//   threads, so no locking is needed.
//
// Allocator discipline follows this file: decoded text and
// cloned names use the given allocator, and error strings
// use fmt.aprintf like the other error paths here.

foreign import icuuc "system:icuuc"
foreign import icui18n "system:icui18n"

UErrorCode :: c.int

// U_SUCCESS as a check, not a symbol: see the gotchas above.
icu_err_ok :: proc(code: UErrorCode) -> bool { return code <= 0 }

// The STOP callback's real signature takes a
// UConverterToUnicodeArgs pointer; rawptr stands in for it
// here because only the function pointer itself is passed,
// never called from Odin code.
UConverterToUCallback :: proc "c" (
	ctx:        rawptr,
	args:      rawptr,
	code_units: [^]u8,
	length:    c.int,
	reason:    c.int,
	err:       ^UErrorCode,
)

foreign icui18n {
	@(link_name="ucsdet_open_74")
	ucsdet_open :: proc(err: ^UErrorCode) -> rawptr ---
	@(link_name="ucsdet_setText_74")
	ucsdet_set_text :: proc(det: rawptr, text: [^]u8, length: c.int, err: ^UErrorCode) ---
	@(link_name="ucsdet_detect_74")
	ucsdet_detect :: proc(det: rawptr, err: ^UErrorCode) -> rawptr ---
	@(link_name="ucsdet_getName_74")
	ucsdet_get_name :: proc(match: rawptr, err: ^UErrorCode) -> cstring ---
	@(link_name="ucsdet_close_74")
	ucsdet_close :: proc(det: rawptr) ---
}

foreign icuuc {
	@(link_name="ucnv_open_74")
	ucnv_open :: proc(name: cstring, err: ^UErrorCode) -> rawptr ---
	@(link_name="ucnv_close_74")
	ucnv_close :: proc(cnv: rawptr) ---
	@(link_name="ucnv_setToUCallBack_74")
	ucnv_set_to_u_callback :: proc(
		cnv:         rawptr,
		new_action:  UConverterToUCallback,
		new_context: rawptr,
		old_action:  ^UConverterToUCallback,
		old_context: ^rawptr,
		err:         ^UErrorCode,
	) ---
	@(link_name="ucnv_toUChars_74")
	ucnv_to_u_chars :: proc(
		cnv:           rawptr,
		dest:          [^]u16,
		dest_capacity: c.int,
		src:           [^]u8,
		src_length:    c.int,
		err:           ^UErrorCode,
	) -> c.int ---
	@(link_name="u_strToUTF8_74")
	u_str_to_utf8 :: proc(
		dest:          [^]u8,
		dest_capacity: c.int,
		p_dest_length: ^c.int,
		src:           [^]u16,
		src_length:    c.int,
		err:           ^UErrorCode,
	) -> c.int ---
	@(link_name="UCNV_TO_U_CALLBACK_STOP_74")
	ucnv_to_u_callback_stop :: proc "c" (
		ctx:        rawptr,
		args:      rawptr,
		code_units: [^]u8,
		length:    c.int,
		reason:    c.int,
		err:       ^UErrorCode,
	) ---
}

// Detect an encoding name for bytes with no BOM. Returns a
// name cloned into the allocator (the detector's own name
// dies with it) and false when detection itself fails, in
// which case the caller falls back to UTF-8.
icu_detect_name :: proc(bytes: []byte, allocator := context.allocator) -> (string, bool) {
	err: UErrorCode = 0
	det := ucsdet_open(&err)
	if !icu_err_ok(err) || det == nil {
		return "", false
	}
	defer ucsdet_close(det)
	ucsdet_set_text(det, raw_data(bytes), c.int(len(bytes)), &err)
	if !icu_err_ok(err) {
		return "", false
	}
	match := ucsdet_detect(det, &err)
	if !icu_err_ok(err) || match == nil {
		return "", false
	}
	cname := ucsdet_get_name(match, &err)
	if !icu_err_ok(err) || cname == nil {
		return "", false
	}
	return strings.clone(string(cname), allocator), true
}

// Convert bytes from a named encoding to UTF-8, strictly:
// any undecodable byte is an error, never a U+FFFD
// substitution (see the STOP-callback gotcha above).
icu_convert_strict :: proc(bytes: []byte, name: string, allocator := context.allocator) -> (string, string) {
	decode_err := fmt.aprintf("Imported text could not be decoded as %s.", name)
	err: UErrorCode = 0
	cname := strings.clone_to_cstring(name, allocator)
	defer delete(cname, allocator)
	cnv := ucnv_open(cname, &err)
	if !icu_err_ok(err) || cnv == nil {
		return "", decode_err
	}
	defer ucnv_close(cnv)
	ucnv_set_to_u_callback(cnv, ucnv_to_u_callback_stop, nil, nil, nil, &err)
	if !icu_err_ok(err) {
		return "", decode_err
	}
	// One UChar per input byte is a safe upper bound for
	// these encodings (UTF-16 input has half as many units
	// as bytes; every other unit here comes from one byte).
	uchars := make([]u16, len(bytes), allocator)
	defer delete(uchars, allocator)
	n := ucnv_to_u_chars(cnv, raw_data(uchars), c.int(len(uchars)), raw_data(bytes), c.int(len(bytes)), &err)
	if !icu_err_ok(err) {
		return "", decode_err
	}
	if n == 0 {
		return "", ""
	}
	// Two-pass UTF-8 sizing: the measuring call is expected
	// to fail with U_BUFFER_OVERFLOW_ERROR (15) and report
	// the length; anything else is a real failure.
	out_len: c.int = 0
	err = 0
	u_str_to_utf8(nil, 0, &out_len, raw_data(uchars), n, &err)
	if err != 15 {
		return "", decode_err
	}
	out := make([]u8, out_len, allocator)
	defer delete(out, allocator)
	err = 0
	u_str_to_utf8(raw_data(out), out_len, &out_len, raw_data(uchars), n, &err)
	if !icu_err_ok(err) {
		return "", decode_err
	}
	return strings.clone(string(out), allocator), ""
}

// Decode import bytes to UTF-8: BOM sniff first, else ICU
// detection, then strict conversion. Empty input decodes to
// empty. The returned text is owned in the given allocator;
// the caller deletes it after parsing.
decode_import_bytes :: proc(bytes: []byte, allocator := context.allocator) -> (string, string) {
	if len(bytes) == 0 {
		return "", ""
	}
	if len(bytes) > int(max(i32)) {
		return "", "Imported text could not be decoded."
	}
	name := ""
	rest := bytes
	if len(bytes) >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf {
		name, rest = "UTF-8", bytes[3:]
	} else if len(bytes) >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe {
		name, rest = "UTF-16LE", bytes[2:]
	} else if len(bytes) >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff {
		name, rest = "UTF-16BE", bytes[2:]
	}
	if len(rest) == 0 {
		return "", ""
	}
	if name == "" {
		detected, ok := icu_detect_name(rest, allocator)
		if !ok {
			return icu_convert_strict(rest, "UTF-8", allocator)
		}
		defer delete(detected, allocator)
		return icu_convert_strict(rest, detected, allocator)
	}
	return icu_convert_strict(rest, name, allocator)
}

// --- HTTP fetching (http:// only) ------------------------------------

Http_Url :: struct {
	host: string,
	port: int,
	path: string,
}

parse_http_url :: proc(url: string) -> (Http_Url, string) {
	if strings.has_prefix(url, "https://") {
		return {}, "HTTPS URLs are not supported by this importer; use an http:// URL (for example, the local test server)."
	}
	if !strings.has_prefix(url, "http://") {
		return {}, "URL must start with http://."
	}
	rest := url[len("http://"):]
	host_port, path := rest, "/"
	if idx := strings.index_byte(rest, '/'); idx >= 0 {
		host_port, path = rest[:idx], rest[idx:]
	}
	if host_port == "" {
		return {}, "URL is missing a host."
	}
	host, port := host_port, 80
	if idx := strings.last_index_byte(host_port, ':'); idx >= 0 {
		port_text := host_port[idx + 1:]
		if port_text != "" {
			parsed, ok := strconv.parse_int(port_text)
			if !ok || parsed < 0 || parsed > 65535 {
				return {}, fmt.aprintf("Invalid port in URL: %s.", port_text)
			}
			host, port = host_port[:idx], int(parsed)
		}
	}
	if host == "" {
		return {}, "URL is missing a host."
	}
	return Http_Url{host = host, port = port, path = path}, ""
}

// Decode a chunked transfer-encoding body: hex size lines (with
// optional ";extension" suffixes), data, CRLF, repeated, ending
// with a zero-size chunk and trailing headers up to a blank line.
decode_chunked :: proc(body: []byte, allocator := context.allocator) -> ([]byte, string) {
	out := make([dynamic]byte, 0, allocator)
	rest := body
	for {
		line_end := bytes.index(rest, []byte{'\r', '\n'})
		if line_end < 0 {
			delete(out)
			return nil, "Malformed chunked response."
		}
		size_text := string(rest[:line_end])
		if idx := strings.index_byte(size_text, ';'); idx >= 0 {
			size_text = size_text[:idx]
		}
		size_text = strings.trim_space(size_text)
		size, ok := strconv.parse_uint(size_text, 16)
		if !ok {
			delete(out)
			return nil, "Malformed chunked response."
		}
		rest = rest[line_end + 2:]
		if size == 0 {
			break
		}
		// Guard the uint -> int conversion: a chunk larger
		// than the remaining input is truncated, never a
		// wrapped-around negative slice bound.
		if size > uint(len(rest)) {
			delete(out)
			return nil, "Truncated chunked response."
		}
		chunk := int(size)
		if len(rest) < chunk + 2 {
			delete(out)
			return nil, "Truncated chunked response."
		}
		append(&out, ..rest[:chunk])
		rest = rest[chunk + 2:]
	}
	return out[:], ""
}

Fetch_Outcome :: union {
	// Body bytes, owned by the caller.
	[]byte,
	// A redirect target (the raw Location value).
	string,
}

fetch_once :: proc(url: Http_Url, allocator := context.allocator) -> (Fetch_Outcome, string) {
	// Network_Error is a union of the net error enums, so a
	// failed dial is a non-nil union, not a .None enum value
	// (unlike the TCP_Recv_Error/TCP_Send_Error enums below,
	// which do have .None).
	socket, net_err := net.dial_tcp_from_hostname_with_port_override(url.host, url.port)
	if net_err != nil {
		return nil, fmt.aprintf("Could not connect to %s: %v.", url.host, net_err)
	}
	defer net.close(socket)

	host_header := url.host
	if url.port != 80 {
		host_header = fmt.aprintf("%s:%d", url.host, url.port)
		defer delete(host_header, allocator)
	}
	request := fmt.aprintf(
		"GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\nUser-Agent: recipe-manager-test\r\nAccept: application/json\r\n\r\n",
		url.path, host_header,
	)
	defer delete(request, allocator)
	if _, net_err := net.send_tcp(socket, transmute([]byte)request); net_err != .None {
		return nil, fmt.aprintf("Could not send request: %v.", net_err)
	}

	// Read to EOF (Connection: close): the server closes the
	// connection when the body is complete, so no Content-Length
	// accounting is needed for the read itself.
	raw := make([dynamic]byte, 0, allocator)
	buf: [4096]byte
	for {
		n, recv_err := net.recv_tcp(socket, buf[:])
		if recv_err != .None {
			delete(raw)
			return nil, fmt.aprintf("Could not read response: %v.", recv_err)
		}
		if n == 0 {
			break
		}
		append(&raw, ..buf[:n])
	}

	header_end := bytes.index(raw[:], []byte{'\r', '\n', '\r', '\n'})
	if header_end < 0 {
		delete(raw)
		return nil, "Response was not valid HTTP."
	}
	headers_text := string(raw[:header_end])
	lines := strings.split_lines(headers_text, allocator)
	defer delete(lines, allocator)
	if len(lines) == 0 {
		delete(raw)
		return nil, "Response was not valid HTTP."
	}
	status_fields := strings.fields(lines[0], allocator)
	defer delete(status_fields, allocator)
	if len(status_fields) < 2 {
		delete(raw)
		return nil, "Response was not valid HTTP."
	}
	status, ok := strconv.parse_int(status_fields[1])
	if !ok {
		delete(raw)
		return nil, "Response was not valid HTTP."
	}

	location := ""
	chunked := false
	content_length := -1
	for line in lines[1:] {
		if idx := strings.index_byte(line, ':'); idx >= 0 {
			name := strings.to_lower(strings.trim_space(line[:idx]), allocator)
			value := strings.trim_space(line[idx + 1:])
			defer delete(name, allocator)
			switch name {
			case "location":
				location = value
			case "transfer-encoding":
				lower := strings.to_lower(value, allocator)
				if strings.contains(lower, "chunked") {
					chunked = true
				}
				delete(lower, allocator)
			case "content-length":
				if parsed, ok := strconv.parse_int(value); ok {
					content_length = int(parsed)
				}
			}
		}
	}
	if status == 301 || status == 302 || status == 303 || status == 307 || status == 308 {
		if location != "" {
			// Clone BEFORE deleting raw: location is a
			// substring of the header text, which aliases
			// raw, so cloning after the delete would read
			// freed memory.
			cloned := strings.clone(location, allocator)
			delete(raw)
			return cloned, ""
		}
	}
	if status != 200 {
		delete(raw)
		return nil, fmt.aprintf("Server returned HTTP %d for %s:%d.", status, url.host, url.port)
	}
	body_bytes := raw[header_end + 4:]
	body: []byte
	if chunked {
		decoded, err := decode_chunked(body_bytes, allocator)
		if err != "" {
			delete(raw)
			return nil, err
		}
		body = decoded
	} else if content_length >= 0 {
		if len(body_bytes) < content_length {
			delete(raw)
			return nil, "Response ended before the full body arrived."
		}
		body = make([]byte, content_length, allocator)
		copy(body, body_bytes[:content_length])
	} else {
		body = make([]byte, len(body_bytes), allocator)
		copy(body, body_bytes)
	}
	delete(raw)
	return body, ""
}

resolve_redirect :: proc(current: Http_Url, location: string, allocator := context.allocator) -> string {
	if strings.has_prefix(location, "http://") || strings.has_prefix(location, "https://") {
		return strings.clone(location, allocator)
	}
	// NOTE: do not build an intermediate host_port string and
	// defer-delete it here. That pattern corrupted the returned
	// string in this Odin version (proven with a standalone
	// probe: the host bytes came back as garbage, same length,
	// whenever the defer was present, and correct without it).
	// Each branch below formats the result in one aprintf, so
	// there is no intermediate to free.
	if strings.has_prefix(location, "/") {
		if current.port == 80 {
			return fmt.aprintf("http://%s%s", current.host, location)
		}
		return fmt.aprintf("http://%s:%d%s", current.host, current.port, location)
	}
	// A relative path resolves against the current path's directory.
	base := "/"
	if idx := strings.last_index_byte(current.path, '/'); idx >= 0 {
		base = current.path[:idx + 1]
	}
	if current.port == 80 {
		return fmt.aprintf("http://%s%s%s", current.host, base, location)
	}
	return fmt.aprintf("http://%s:%d%s%s", current.host, current.port, base, location)
}

// Fetch a document body (owned by the caller), following up to
// 3 redirects like the Rust version (an initial fetch plus 3
// redirect fetches, then "Too many redirects."). Recursion
// keeps ownership simple: each level frees its own redirect
// target after the level below returns.
fetch_url :: proc(url: string, allocator := context.allocator) -> ([]byte, string) {
	return fetch_url_n(url, 3, allocator)
}

fetch_url_n :: proc(url: string, redirects_left: int, allocator := context.allocator) -> ([]byte, string) {
	parsed, err := parse_http_url(url)
	if err != "" {
		return nil, err
	}
	outcome, ferr := fetch_once(parsed, allocator)
	if ferr != "" {
		return nil, ferr
	}
	switch v in outcome {
	case []byte:
		return v, ""
	case string:
		if redirects_left <= 0 {
			delete(v, allocator)
			return nil, "Too many redirects."
		}
		next := resolve_redirect(parsed, v, allocator)
		delete(v, allocator)
		body, rerr := fetch_url_n(next, redirects_left - 1, allocator)
		delete(next, allocator)
		return body, rerr
	}
	return nil, "Too many redirects."
}

// Fetch a document and parse it. This is what the worker thread
// runs, so a slow server or a large document never blocks the UI.
// The body is decoded (see the text-encoding section) before
// parsing, so a non-UTF-8 document is an import error, never
// garbled text.
fetch_and_parse :: proc(url: string, allocator := context.allocator) -> ([]Recipe, string) {
	body, err := fetch_url(url, allocator)
	if err != "" {
		return nil, err
	}
	defer delete(body, allocator)
	text, derr := decode_import_bytes(body, allocator)
	if derr != "" {
		return nil, derr
	}
	defer delete(text, allocator)
	return parse_recipes(text, allocator)
}

// --- Raw-file import ---------------------------------------------------

// Read a recipe document from a file and parse it with the
// same parse_recipes the URL importer uses: the same three
// shapes and the same defaults. The bytes are decoded (see
// the text-encoding section) before parsing, so a file in
// UTF-16, Windows-1252, or Shift_JIS imports as UTF-8, and
// an undecodable file is a read failure, never garbled text.
// This is what the worker thread runs, so reading and parsing
// never block the UI.
import_from_file :: proc(path: string, allocator := context.allocator) -> ([]Recipe, string) {
	data, err := os.read_entire_file(path, allocator)
	if err != nil {
		return nil, fmt.aprintf("Could not read file %s: %v.", path, err)
	}
	defer delete(data, allocator)
	text, derr := decode_import_bytes(data, allocator)
	if derr != "" {
		return nil, fmt.aprintf("Could not read file %s: %s.", path, derr)
	}
	defer delete(text, allocator)
	return parse_recipes(text, allocator)
}

// --- Worker thread + main-thread poll -------------------------------

// Shared with the import worker thread. The worker fills
// recipes or err and returns; the main thread reads those
// fields only after joining the thread, so there is no race
// on them. recipes owns its strings (see the file header).
// Exactly one source is set: url for a URL import, path for
// a file import; the other stays "" (the zero value, never a
// heap string), so poll/discard free only the non-empty one.
// Both strings are heap-cloned by the main thread when set.
Import_Job :: struct {
	url:     string,
	path:    string,
	recipes: []Recipe,
	err:     string,
}

import_job_proc :: proc(job: ^Import_Job) {
	// Give the worker its own temp allocator. The worker
	// inherits the creating thread's context, so without this
	// its temp allocator would be the main thread's — which
	// the frame loop frees every frame — and core:net uses
	// the temp allocator for DNS resolution scratch. A 1 MiB
	// arena is far more than a hostname lookup needs, and it
	// is freed when the worker returns.
	arena_buf := make([]byte, 1 << 20)
	defer delete(arena_buf)
	arena: mem.Arena
	mem.arena_init(&arena, arena_buf)
	context.temp_allocator = mem.arena_allocator(&arena)
	if job.path != "" {
		recipes, err := import_from_file(job.path)
		job.recipes, job.err = recipes, err
	} else {
		recipes, err := fetch_and_parse(job.url)
		job.recipes, job.err = recipes, err
	}
}

// Collect a finished import, URL or file, if any, without
// blocking: thread.is_done only. The worker already fetched
// or read and parsed, so this step is just the database
// inserts, using the same insert_recipe the Add form uses.
// A failed insert stops the import, leaving any recipes
// already inserted in place. On success first_id is the id
// of the first inserted recipe (-1 when nothing was
// inserted); the caller reloads from the database, rebuilds
// the list, and reselects first_id. Exactly one of message
// and err is set on completion; both are "" while the job
// is still running. Returns false while the job is running,
// true once it has been collected (or when there is no job).
collect_import_job :: proc(
	db: ^Sqlite_Db,
	job_thread: ^^thread.Thread,
	job: ^^Import_Job,
) -> (first_id: i64, message: string, err: string, done: bool) {
	if job_thread^ == nil || job^ == nil {
		return -1, "", "", true
	}
	if !thread.is_done(job_thread^) {
		return -1, "", "", false
	}
	thread.join(job_thread^)
	thread.destroy(job_thread^)
	job_thread^ = nil
	j := job^
	job^ = nil
	defer free(j)
	if len(j.url) > 0 {
		delete(j.url)
	}
	if len(j.path) > 0 {
		delete(j.path)
	}
	if j.err != "" {
		// Transfer ownership of the worker's error string to
		// the caller: it was built on the heap allocator, so
		// it stays valid after the worker is gone.
		err = j.err
		free_imported_recipes(j.recipes)
		return -1, "", err, true
	}
	total := len(j.recipes)
	inserted := 0
	first_id = -1
	failed := ""
	for recipe in j.recipes {
		r := recipe
		id, dberr := insert_recipe(db, r)
		if dberr != "" {
			failed = dberr
			break
		}
		r.id = id
		if first_id < 0 {
			first_id = id
		}
		inserted += 1
	}
	// Free the uninserted tail (the failed recipe and the
	// rest); the inserted ones are in the database now, and
	// the caller reloads them from it.
	for i := inserted; i < len(j.recipes); i += 1 {
		free_recipe_strings(j.recipes[i])
	}
	delete(j.recipes)
	if failed != "" {
		// Clone: failed came from db_error, which builds on
		// the temp allocator, so it would not survive the
		// caller otherwise.
		err = strings.clone(failed)
		return -1, "", err, true
	}
	if total == 1 {
		message = fmt.aprintf("Imported 1 recipe.")
	} else {
		message = fmt.aprintf("Imported %d recipes.", total)
	}
	return first_id, message, "", true
}

// Join and discard an import still in flight (for example when
// the window closes): its recipes were never inserted, so they
// are freed rather than kept.
discard_import_job :: proc(job_thread: ^^thread.Thread, job: ^^Import_Job) {
	if job_thread^ == nil || job^ == nil {
		return
	}
	thread.join(job_thread^)
	thread.destroy(job_thread^)
	job_thread^ = nil
	j := job^
	job^ = nil
	defer free(j)
	if len(j.url) > 0 {
		delete(j.url)
	}
	if len(j.path) > 0 {
		delete(j.path)
	}
	free_imported_recipes(j.recipes)
}
