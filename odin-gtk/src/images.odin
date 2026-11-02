package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"
import gobj "../third_party/odin-gtk/glib/gobject"
import gtk "../third_party/odin-gtk/gtk"
import pixbuf "../third_party/odin-gtk/gdk-pixbuf"

// Image display and import, following cpp-gtk4's shape:
// images decode on a worker thread (gdk-pixbuf is thread-safe
// for independent pixbufs), the GdkTexture is created on the
// main thread from the decoded pixbuf, and the list shows a
// spinner while a recipe's image is decoding. A path that
// fails to decode is remembered as failed and never retried.
// Textures are never evicted once created.
//
// The detail pane shows the photo at up to 400x300 (the
// decode scales down to fit that box, preserving aspect),
// the list shows a 32x32 thumbnail of the same texture.
// The form's "Choose image..." button copies the chosen file
// into images/ next to recipes.db (with a _1/_2 suffix on
// collision) and stores the relative path, so the image
// survives a restart in the same directory.

// One decode job. The worker fills pixbuf or failed and
// returns; the main thread reads those fields only after
// joining, so there is no race on them. path is heap-owned
// by the job (cloned when the job is made, deleted when it
// is collected).
Image_Job :: struct {
	path:   string,
	pixbuf: ^pixbuf.Pixbuf,
	failed: bool,
	// Set by the creator right after the thread starts;
	// only the main thread reads it (in poll_image_jobs).
	thread: ^thread.Thread,
}

Image_Row_Ref :: struct {
	path:                  string, // aliases a recipe's image_path; not owned
	picture, spinner:      ^gtk.Widget,
	placeholder:           ^gtk.Widget,
}

image_textures: map[string]^gtk.Texture
image_failed:   map[string]bool
image_jobs:     [dynamic]^Image_Job
image_row_refs: [dynamic]Image_Row_Ref

// copy_image_file copies src into dest_dir (default images/
// in the current directory), returning the path to store
// ("images/<name>"). A name collision appends _1, _2, ...
// before the extension, like cpp-imgui's picker does. The
// make_directory error is ignored on purpose: an existing
// directory errors, and a real failure surfaces at the
// write below with the destination in the message.
copy_image_file :: proc(src: string, dest_dir := "images", allocator := context.allocator) -> (string, string) {
	os.make_directory(dest_dir)
	base := filepath.base(src)
	stem, ext := base, ""
	if i := strings.last_index_byte(base, '.'); i > 0 {
		stem, ext = base[:i], base[i:]
	}
	for n := 0; ; n += 1 {
		name := base
		if n > 0 {
			name = fmt.tprintf("%s_%d%s", stem, n, ext)
		}
		dest := fmt.tprintf("%s/%s", dest_dir, name)
		if !os.exists(dest) {
			data, rerr := os.read_entire_file(src, allocator)
			if rerr != nil {
				return "", fmt.aprintf("Could not read file %s: %v.", src, rerr, allocator = allocator)
			}
			defer delete(data, allocator)
			if werr := os.write_entire_file(dest, data); werr != nil {
				return "", fmt.aprintf("Could not write file %s: %v.", dest, werr, allocator = allocator)
			}
			return strings.clone(dest, allocator), ""
		}
	}
}

image_job_proc :: proc(data: rawptr) {
	job := (^Image_Job)(data)
	cs := strings.clone_to_cstring(job.path)
	defer delete(cs)
	pb := pixbuf.pixbuf_new_from_file(cs, nil)
	if pb == nil {
		job.failed = true
		return
	}
	w := pixbuf.pixbuf_get_width(pb)
	h := pixbuf.pixbuf_get_height(pb)
	scale := 1.0
	if w > 400 || h > 300 {
		sw := 400.0 / f64(w)
		sh := 300.0 / f64(h)
		scale = min(sw, sh)
	}
	nw := i32(f64(w) * scale)
	nh := i32(f64(h) * scale)
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	if scale < 1.0 {
		scaled := pixbuf.pixbuf_scale_simple(pb, nw, nh, pixbuf.InterpType.BILINEAR)
		gobj.object_unref(pb)
		if scaled == nil {
			job.failed = true
			return
		}
		job.pixbuf = scaled
	} else {
		job.pixbuf = pb
	}
}

image_job_running :: proc(path: string) -> bool {
	for job in image_jobs {
		if job.path == path {
			return true
		}
	}
	return false
}

// start_image_loads starts a decode for every recipe image
// that has no texture yet, has not failed, and is not
// already loading.
start_image_loads :: proc() {
	for r in recipes {
		if r.image_path == "" {
			continue
		}
		if r.image_path in image_textures || r.image_path in image_failed {
			continue
		}
		if image_job_running(r.image_path) {
			continue
		}
		job := new(Image_Job)
		job.path = strings.clone(r.image_path)
		job.thread = thread.create_and_start_with_data(job, image_job_proc)
		append(&image_jobs, job)
	}
}

// refresh_detail_image shows the right detail-image state
// for detail_image_path: the photo when its texture is
// ready, the spinner while it decodes, an error line when
// it failed, nothing when the recipe has no image.
refresh_detail_image :: proc() {
	d := detail_ptr
	if d == nil || d.image_picture == nil {
		return
	}
	path := detail_image_path
	if path == "" {
		gtk.widget_set_visible(d.image_picture, false)
		gtk.widget_set_visible(d.image_spinner_box, false)
		gtk.widget_set_visible(d.image_status, false)
		set_text(d.image_status, "")
		return
	}
	if tex, ok := image_textures[path]; ok {
		gtk.picture_set_paintable(
			cast(^gtk.Picture)d.image_picture,
			cast(^gtk.Paintable)tex,
		)
		gtk.widget_set_visible(d.image_picture, true)
		gtk.widget_set_visible(d.image_spinner_box, false)
		gtk.widget_set_visible(d.image_status, false)
		set_text(d.image_status, "")
		return
	}
	if path in image_failed {
		gtk.widget_set_visible(d.image_picture, false)
		gtk.widget_set_visible(d.image_spinner_box, false)
		gtk.widget_set_visible(d.image_status, true)
		set_text(d.image_status, "Could not load image.")
		return
	}
	gtk.widget_set_visible(d.image_picture, false)
	gtk.widget_set_visible(d.image_spinner_box, true)
	gtk.widget_set_visible(d.image_status, false)
	set_text(d.image_status, "")
}

refresh_row_ref :: proc(ref: Image_Row_Ref) {
	if tex, ok := image_textures[ref.path]; ok {
		gtk.picture_set_paintable(
			cast(^gtk.Picture)ref.picture,
			cast(^gtk.Paintable)tex,
		)
		gtk.widget_set_visible(ref.picture, true)
		gtk.widget_set_visible(ref.spinner, false)
		gtk.widget_set_visible(ref.placeholder, false)
		return
	}
	if ref.path in image_failed || ref.path == "" {
		gtk.widget_set_visible(ref.picture, false)
		gtk.widget_set_visible(ref.spinner, false)
		gtk.widget_set_visible(ref.placeholder, true)
		return
	}
	gtk.widget_set_visible(ref.picture, false)
	gtk.widget_set_visible(ref.spinner, true)
	gtk.widget_set_visible(ref.placeholder, false)
}

// poll_image_jobs collects finished decodes: the texture
// is created here, on the main thread, and every widget
// showing that path is updated in place.
poll_image_jobs :: proc() {
	for i := len(image_jobs) - 1; i >= 0; i -= 1 {
		job := image_jobs[i]
		if job.thread == nil || !thread.is_done(job.thread) {
			continue
		}
		thread.join(job.thread)
		thread.destroy(job.thread)
		ordered_remove(&image_jobs, i)
		if job.failed || job.pixbuf == nil {
			image_failed[job.path] = true
		} else {
			tex := gtk.gdk_texture_new_for_pixbuf(job.pixbuf)
			gobj.object_unref(job.pixbuf)
			if tex == nil {
				image_failed[job.path] = true
			} else {
				image_textures[job.path] = tex
			}
		}
		for ref in image_row_refs {
			if ref.path == job.path {
				refresh_row_ref(ref)
			}
		}
		if detail_image_path == job.path {
			refresh_detail_image()
		}
		delete(job.path)
		free(job)
	}
}

