package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import rl "vendor:raylib"

// Image files and asynchronous image loading.
//
// Import: raylib has no file picker dialog, so the edit form
// takes a source file path in a text field and an Import button
// copies that file into images/ next to recipes.db (mirroring
// the Rust version's import_image in rust-egui/src/images.rs:
// the stored copy keeps working if the original is moved).
// On a name collision the copy gets a _1, _2 suffix, and the
// form's image path is replaced with the stored copy's path.
// A path typed into the form without importing is stored as
// typed, like a path the Rust file dialog would have returned.
//
// Loading state: decoding runs on a worker thread, one per
// image path, so a large image never blocks the UI thread
// (the Rust version does the same with a thread + channel).
// The worker only decodes into CPU memory with LoadImage —
// no GPU call — and reports back through a mutex-guarded
// flag. The main thread polls that flag each frame and, once
// decoding is done, uploads the texture with
// LoadTextureFromImage (a GPU call, so it must happen on the
// main thread) and frees the decoded pixels. While a path is
// loading, the list and detail panes draw a spinner instead
// of an image; on failure they show the error text, and the
// failed path is not retried every frame (its entry stays in
// the Failed state).

Image_State :: enum {
	Loading,
	Ready,
	Failed,
}

Image_Entry :: struct {
	path:       string,
	path_cstr:  cstring,
	state:      Image_State,
	texture:    rl.Texture2D,
	has_texture: bool,
	// Written by the worker thread, read by the main thread,
	// both sides under mutex. pending_done is set once by the
	// worker and cleared once by the main thread when it
	// consumes the result, so there is no repeated upload.
	pending_image: rl.Image,
	pending_ok:    bool,
	pending_done:  bool,
	mutex:         sync.Mutex,
	thread:        ^thread.Thread,
}

// Keyed by image path. Never evicted in this version; fine
// for a small test app. Package-level, like the recipe data:
// entries are heap-allocated and live for the program's life.
image_entries: map[string]^Image_Entry

image_decode_thread :: proc(entry: ^Image_Entry) {
	img := rl.LoadImage(entry.path_cstr)
	sync.mutex_lock(&entry.mutex)
	if img.data == nil {
		entry.pending_ok = false
	} else {
		entry.pending_image = img
		entry.pending_ok = true
	}
	entry.pending_done = true
	sync.mutex_unlock(&entry.mutex)
}

// Return the entry for a path, spawning its decode thread on
// first use. Callers must have a current raylib window: the
// texture upload in image_poll needs the GL context, which
// only exists after InitWindow.
image_ensure :: proc(path: string) -> ^Image_Entry {
	if entry, ok := image_entries[path]; ok {
		return entry
	}
	entry := new(Image_Entry)
	entry.path = path
	entry.path_cstr = strings.clone_to_cstring(path)
	entry.state = .Loading
	image_entries[path] = entry
	entry.thread = thread.create_and_start_with_poly_data(entry, image_decode_thread)
	return entry
}

// Advance every in-flight decode: upload finished decodes to
// textures on this (main) thread, mark failures. Called once
// per frame, before drawing.
image_poll :: proc() {
	for _, entry in image_entries {
		sync.mutex_lock(&entry.mutex)
		done := entry.pending_done
		ok := entry.pending_ok
		img := entry.pending_image
		sync.mutex_unlock(&entry.mutex)
		if !done || entry.has_texture {
			continue
		}
		// Consume the result so this upload runs exactly once.
		sync.mutex_lock(&entry.mutex)
		entry.pending_done = false
		sync.mutex_unlock(&entry.mutex)
		if ok {
			entry.texture = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
			entry.has_texture = true
			entry.state = .Ready
		} else {
			entry.state = .Failed
		}
	}
}

// Free every uploaded texture. Called once at shutdown; worker
// threads still decoding are left to die with the process,
// since joining them could stall shutdown on a huge decode.
image_cleanup :: proc() {
	for _, entry in image_entries {
		if entry.has_texture {
			rl.UnloadTexture(entry.texture)
			entry.has_texture = false
		}
	}
}

// Copy a file into images/, with a _1, _2 suffix on collision.
// Returns the stored path (owned string), or an error message.
import_image :: proc(source: string) -> (string, string) {
	if !os.exists(source) {
		return "", fmt.tprintf("Image file not found: %s", source)
	}
	if !os.exists("images") {
		if err := os.make_directory("images"); err != nil {
			return "", fmt.tprintf("Could not create images directory: %v", err)
		}
	}
	base := filepath.base(source)
	ext := filepath.ext(base)
	stem := base[:len(base)-len(ext)]
	dest, _ := filepath.join({"images", base})
	counter := 1
	for os.exists(dest) {
		delete(dest)
		dest, _ = filepath.join({"images", fmt.aprintf("%s_%d%s", stem, counter, ext)})
		counter += 1
	}
	data, err := os.read_entire_file(source, context.allocator)
	if err != nil {
		delete(dest)
		return "", fmt.tprintf("Could not read image file: %v", err)
	}
	defer delete(data)
	if werr := os.write_entire_file(dest, data); werr != nil {
		delete(dest)
		return "", fmt.tprintf("Could not copy image: %v", werr)
	}
	return dest, ""
}
