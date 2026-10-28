package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:thread"

import stbi "vendor:stb/image"
import rl "vendor:raylib"

// Image files on disk, and asynchronous image loading.
//
// IMPORT: raylib has no file picker, so unlike the Rust
// version — which pops up an rfd file dialog — this version
// imports from a path typed into a text field in the edit
// form. import_image copies that file into images/ next to
// recipes.db (git-ignored), like the Rust version, and never
// overwrites: a second import of the same filename gets a
// _1, _2 suffix. The stored image_path is the copied path.
//
// LOADING: decoding happens on a worker thread, so a large
// image never blocks the UI. The worker decodes with stb_image
// (vendor:stb/image) — never raylib, whose calls are not
// thread-safe — into an RGBA pixel buffer, and the main
// thread uploads that buffer to a GPU texture with
// LoadTextureFromImage, which must run on the main thread.
// While a path is Loading, the list and detail panes draw a
// spinner for it instead of an image; a failed decode is
// remembered as Failed, so it is not retried every frame.
//
// The worker thread touches no microUI or raylib state and
// allocates nothing on the shared temp allocator: it reads
// the file with the plain heap allocator and decodes with
// stb_image's own malloc'd buffer, so the main thread's temp
// allocator (freed every frame) is never involved.

import_image :: proc(source: string) -> (string, string) {
	data, err := os.read_entire_file(source, context.allocator)
	if err != nil {
		return "", fmt.tprintf("Could not read %s.", source)
	}
	defer delete(data)
	if !os.exists("images") {
		if err := os.make_directory("images"); err != nil {
			return "", fmt.tprintf("Could not create images directory: %v.", err)
		}
	}
	// filepath.base/stem/ext live in core:path/filepath, but
	// join returns a second Allocator_Error value; plain
	// concatenation is simpler here and returns one string.
	base := source
	if idx := strings.last_index_byte(source, '/'); idx >= 0 {
		base = source[idx + 1:]
	}
	dest := strings.concatenate({"images/", base})
	if os.exists(dest) {
		stem, ext := base, ""
		if idx := strings.last_index_byte(base, '.'); idx > 0 {
			stem, ext = base[:idx], base[idx:]
		}
		counter := 1
		for {
			candidate := strings.concatenate({"images/", stem, fmt.tprintf("_%d", counter), ext})
			if !os.exists(candidate) {
				dest = candidate
				break
			}
			counter += 1
		}
	}
	if err := os.write_entire_file(dest, data); err != nil {
		return "", fmt.tprintf("Could not copy image to %s.", dest)
	}
	return dest, ""
}

// Shared with the decode worker thread. The worker fills
// pixels/width/height (or failed) and returns; the main
// thread reads those fields only after joining the thread,
// so there is no race on them.
Image_Job :: struct {
	path:   string,
	pixels: [^]u8,
	width:  i32,
	height: i32,
	failed: bool,
}

decode_image_job :: proc(job: ^Image_Job) {
	data, err := os.read_entire_file(job.path, context.allocator)
	if err != nil {
		job.failed = true
		return
	}
	defer delete(data, context.allocator)
	w, h, channels_in_file: c.int
	pixels := stbi.load_from_memory(raw_data(data), c.int(len(data)), &w, &h, &channels_in_file, 4)
	if pixels == nil {
		job.failed = true
		return
	}
	job.pixels, job.width, job.height = pixels, w, h
}

Image_State :: enum {
	Loading,
	Loaded,
	Failed,
}

Image_Entry :: struct {
	state:   Image_State,
	texture: rl.Texture2D,
	thumb:   rl.Texture2D,
	job:     ^Image_Job,
	thread:  ^thread.Thread,
}

// Start decoding every recipe image that is not already
// cached, failed, or loading. One worker thread per image
// path, like the Rust version's poll_image_loads.
ensure_image_loads :: proc(cache: ^map[string]^Image_Entry, recipes: []Recipe) {
	for recipe in recipes {
		if recipe.image_path == "" {
			continue
		}
		if _, ok := cache^[recipe.image_path]; ok {
			continue
		}
		job := new(Image_Job)
		job.path = recipe.image_path
		entry := new(Image_Entry)
		entry.state = .Loading
		entry.job = job
		entry.thread = thread.create_and_start_with_poly_data(job, decode_image_job)
		cache^[recipe.image_path] = entry
	}
}

// Collect decodes that have finished and turn them into
// textures on the main thread. The detail texture keeps the
// full decoded size (scaled at draw time to at most 400x300);
// the thumbnail is a second texture resized to exactly 32x32,
// like the Rust version's 32x32 list thumbnail. UnloadImage
// frees the stb pixel buffer with free(), which matches
// stb_image's malloc.
poll_image_loads :: proc(cache: ^map[string]^Image_Entry) {
	for _, entry in cache^ {
		if entry.state != .Loading {
			continue
		}
		if !thread.is_done(entry.thread) {
			continue
		}
		thread.join(entry.thread)
		thread.destroy(entry.thread)
		entry.thread = nil
		job := entry.job
		if job.failed || job.pixels == nil {
			entry.state = .Failed
			continue
		}
		img := rl.Image{
			data    = job.pixels,
			width   = job.width,
			height  = job.height,
			mipmaps = 1,
			format  = .UNCOMPRESSED_R8G8B8A8,
		}
		entry.texture = rl.LoadTextureFromImage(img)
		thumb_img := rl.ImageCopy(img)
		rl.ImageResize(&thumb_img, 32, 32)
		entry.thumb = rl.LoadTextureFromImage(thumb_img)
		rl.UnloadImage(thumb_img)
		rl.UnloadImage(img)
		entry.state = .Loaded
	}
}

// Free every cached texture, joining any decode still in
// flight first. Call before CloseWindow: texture unloading
// needs a live GL context.
cleanup_images :: proc(cache: ^map[string]^Image_Entry) {
	for _, entry in cache^ {
		if entry.state == .Loading && entry.thread != nil {
			thread.join(entry.thread)
			thread.destroy(entry.thread)
			if entry.job != nil && entry.job.pixels != nil {
				stbi.image_free(entry.job.pixels)
			}
		} else if entry.state == .Loaded {
			rl.UnloadTexture(entry.texture)
			rl.UnloadTexture(entry.thumb)
		}
	}
	delete(cache^)
}
