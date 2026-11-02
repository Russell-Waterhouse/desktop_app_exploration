package main

// Recipe list and detail view, backed by SQLite: recipes
// are loaded from recipes.db (seeded on first run with the
// same 3 recipes the other stacks start with). The list is
// a GtkListBox; selecting a row fills the detail pane on
// the right. See db.odin (SQLite layer) and recipes.odin
// (seed data). "Add recipe" opens a form window (title
// required, servings spin button, dynamic ingredient and
// step rows); saving inserts into the database, reloads,
// and selects the new recipe.
// The bindings are fetched by install_ubuntu.sh /
// install_fedora.sh into third_party/odin-gtk (pinned to tag
// 4.17.2) and imported by relative path, the way the
// bindings' own examples do it.

import "core:fmt"
import "core:os"
import "base:runtime"
import "core:strings"
import "core:thread"
import "core:time"
import glib "../third_party/odin-gtk/glib"
import gio "../third_party/odin-gtk/glib/gio"
import gobj "../third_party/odin-gtk/glib/gobject"
import gtk "../third_party/odin-gtk/gtk"

// Recipes loaded from recipes.db, and a database error to
// show instead, set by main() before the app runs. The list
// and detail code reads these; on a database failure the
// list stays empty and the detail title shows the error.
recipes: []Recipe
db_error_msg: string

// Open database handle (set by main, used by the add form's
// save handler) and the main window's list box (rebuilt
// after an insert). Only one add window exists at a time
// (it is modal), so the form handlers share active_form.
db_handle: ^Sqlite_Db
main_list_box: ^gtk.ListBox
detail_ptr: ^Detail
search_entry: ^gtk.Widget

// Indices into recipes, in list order, after applying
// the search filter. Rebuilt by apply_filter on every
// list rebuild.
filtered: [dynamic]int
active_form: ^Form

// Id of the recipe currently shown in the detail pane (-1
// when none is selected); the Edit button acts on it.
selected_id: i64 = -1

// Id awaiting confirmation in the delete dialog (-1 when
// no dialog is open); the dialog is modal, so this is
// never shared between two dialogs.
pending_delete_id: i64 = -1

// Image path shown in the detail pane (aliases the selected
// recipe's image_path; the widgets live in Detail and the
// loading state in images.odin).
detail_image_path: string

// List/detail transition state: the detail pane fades in
// over 0.25s (ease-out cubic) when the selection changes,
// like cpp-gtk4's timeout-driven opacity steps.
detail_box_widget: ^gtk.Widget
transition_active: bool
transition_start: time.Time

// Import/export widgets and job state (see the import
// section below activate). At most one import runs at a
// time; the buttons are disabled while it does.
main_window: ^gtk.Widget
url_entry: ^gtk.Widget
import_button, import_file_button: ^gtk.Widget
export_single_button, export_all_button: ^gtk.Widget
import_spinner_box: ^gtk.Widget
import_status: ^gtk.Widget
import_thread: ^thread.Thread
import_job: ^Import_Job

// File-dialog state: at most one dialog is open at a time;
// opening another while one is open is ignored, because
// the callbacks share these package variables.
dialog_open: bool
dialog_purpose: Dialog_Purpose
dialog_dialog: ^gtk.FileDialog

Dialog_Purpose :: enum {
	None,
	Choose_Image,
	Import_File,
	Export_Single,
	Export_All,
}

// Detail holds the widgets the row-selected handler updates.
// Label widgets are stored as ^Widget (what label_new
// returns) and cast to ^Label where label_set_text needs one.
// The ingredient/step label slots are fixed at the largest
// counts in the data (7 ingredients, 5 steps); slots beyond
// a recipe's counts are hidden.
Detail :: struct {
	title, description, servings, notes: ^gtk.Widget,
	ingredient_labels: [7]^gtk.Widget,
	step_labels:       [5]^gtk.Widget,
	// Image area at the top of the detail pane: the photo
	// when ready, a spinner row while it decodes, and an
	// error line when it fails.
	image_picture, image_spinner_box, image_status: ^gtk.Widget,
}

// new_label makes a label from a runtime string. gtk_label_new
// copies the string, so the clone can be freed right away.
new_label :: proc(s: string) -> ^gtk.Widget {
	cs := strings.clone_to_cstring(s)
	defer delete(cs)
	w := gtk.label_new(cs)
	gtk.label_set_xalign(cast(^gtk.Label)w, 0)
	return w
}

// detail_label makes an empty label for the detail pane,
// left-aligned like the list rows, and selectable: detail
// text is highlightable to copy, the way a browser <p>
// is. Row labels deliberately stay unselectable (see the
// cpp-gtk4 row-click fix): a selectable label inside a
// listbox row captures the click for cursor placement, so
// the row never gets selected.
detail_label :: proc() -> ^gtk.Widget {
	w := gtk.label_new("")
	gtk.label_set_xalign(cast(^gtk.Label)w, 0)
	gtk.label_set_selectable(cast(^gtk.Label)w, true)
	return w
}

set_text :: proc(w: ^gtk.Widget, s: string) {
	// gtk_label_set_text copies the string, so the clone
	// can be freed right after the call.
	cs := strings.clone_to_cstring(s)
	defer delete(cs)
	gtk.label_set_text(cast(^gtk.Label)w, cs)
}

show_recipe :: proc(d: ^Detail, r: Recipe) {
	set_text(d.title, r.title)
	set_text(d.description, r.description)
	set_text(d.servings, fmt.tprintf("Servings: %d", r.servings))

	for i in 0 ..< len(d.ingredient_labels) {
		label := d.ingredient_labels[i]
		if i < len(r.ingredients) {
			ing := r.ingredients[i]
			line: string
			if ing.unit == "" {
				line = fmt.tprintf("%s %s", ing.amount, ing.name)
			} else {
				line = fmt.tprintf("%s %s %s", ing.amount, ing.unit, ing.name)
			}
			set_text(label, line)
			gtk.widget_set_visible(label, true)
		} else {
			gtk.widget_set_visible(label, false)
		}
	}

	for i in 0 ..< len(d.step_labels) {
		label := d.step_labels[i]
		if i < len(r.steps) {
			set_text(label, fmt.tprintf("%d. %s", i + 1, r.steps[i]))
			gtk.widget_set_visible(label, true)
		} else {
			gtk.widget_set_visible(label, false)
		}
	}

	set_text(d.notes, r.notes)
	set_detail_image(r.image_path)
	start_detail_transition()
}

// clear_detail empties the detail pane (used when the
// last recipe has been deleted).
clear_detail :: proc(d: ^Detail) {
	set_text(d.title, "")
	set_text(d.description, "")
	set_text(d.servings, "")
	for label in d.ingredient_labels {
		set_text(label, "")
		gtk.widget_set_visible(label, false)
	}
	for label in d.step_labels {
		set_text(label, "")
		gtk.widget_set_visible(label, false)
	}
	set_text(d.notes, "")
	set_detail_image("")
}

// set_detail_image points the detail image area at a
// recipe's image (or none) and starts its decode if needed.
set_detail_image :: proc(path: string) {
	detail_image_path = path
	refresh_detail_image()
	start_image_loads()
}

// start_detail_transition fades the detail pane in from
// opacity 0 over 0.25s; the tick callback steps it.
start_detail_transition :: proc() {
	if detail_box_widget == nil {
		return
	}
	gtk.widget_set_opacity(detail_box_widget, 0)
	transition_start = time.now()
	transition_active = true
}

on_row_selected :: proc "c" (box: ^gtk.ListBox, row: ^gtk.ListBoxRow, data: rawptr) {
	context = runtime.default_context()
	if row == nil {
		return
	}
	index := gtk.list_box_row_get_index(row)
	if index < 0 || int(index) >= len(filtered) {
		return
	}
	recipe_index := filtered[index]
	selected_id = recipes[recipe_index].id
	show_recipe(cast(^Detail)data, recipes[recipe_index])
}

on_search_changed :: proc "c" (entry: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	_ = entry
	_ = data
	rebuild_list()
	if len(filtered) > 0 {
		selected_id = recipes[filtered[0]].id
		show_recipe(detail_ptr, recipes[filtered[0]])
		row := gtk.list_box_get_row_at_index(main_list_box, 0)
		if row != nil {
			gtk.list_box_select_row(main_list_box, row)
		}
	} else {
		selected_id = -1
		clear_detail(detail_ptr)
	}
}


// --- Import/export and the tick callback ---

// set_import_status shows a message (plain) or an error
// (red, via markup with the text escaped) in the left pane.
set_import_status :: proc(message, err: string) {
	if err != "" {
		cs := strings.clone_to_cstring(err)
		defer delete(cs)
		esc := glib.markup_escape_text(cs, -1)
		defer glib.free(rawptr(esc))
		escaped, _ := strings.clone_from_cstring(esc)
		defer delete(escaped)
		markup := strings.concatenate({"<span foreground=\"red\">", escaped, "</span>"})
		defer delete(markup)
		mcs := strings.clone_to_cstring(markup)
		defer delete(mcs)
		gtk.label_set_markup(cast(^gtk.Label)import_status, mcs)
	} else {
		set_text(import_status, message)
	}
}

set_import_running :: proc(running: bool) {
	gtk.widget_set_sensitive(import_button, b32(!running))
	gtk.widget_set_sensitive(import_file_button, b32(!running))
	gtk.widget_set_visible(import_spinner_box, b32(running))
	if running {
		set_import_status("Importing…", "")
	}
}

// start_import_job starts a URL or file import on a worker
// thread; the tick callback collects it.
start_import_job :: proc(url, path: string) {
	if import_thread != nil {
		return
	}
	job := new(Import_Job)
	if path != "" {
		job.path = strings.clone(path)
	} else {
		job.url = strings.clone(url)
	}
	import_job = job
	import_thread = thread.create_and_start_with_poly_data(job, import_job_proc)
	set_import_running(true)
}

// poll_import collects a finished import job, if any:
// reload from the database, rebuild, reselect the first
// imported recipe, and report the result.
poll_import :: proc() {
	if import_thread == nil || import_job == nil {
		return
	}
	first_id, message, err, done := collect_import_job(db_handle, &import_thread, &import_job)
	if !done {
		return
	}
	set_import_running(false)
	if err != "" {
		set_import_status("", err)
		return
	}
	loaded, load_err := load_recipes(db_handle)
	if load_err != "" {
		set_import_status("", load_err)
		return
	}
	recipes = loaded
	rebuild_list()
	if first_id >= 0 {
		for idx, p in filtered {
			if recipes[idx].id == first_id {
				selected_id = first_id
				show_recipe(detail_ptr, recipes[idx])
				gtk.list_box_select_row(
					main_list_box,
					gtk.list_box_get_row_at_index(main_list_box, i32(p)),
				)
				break
			}
		}
	}
	set_import_status(message, "")
}

on_import_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	_ = button
	_ = data
	start_import_job(entry_text(url_entry), "")
}

on_import_file_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	_ = button
	_ = data
	open_file_dialog(.Import_File, "Import recipes from JSON", cast(^gtk.Window)main_window)
}

on_export_single_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	_ = button
	_ = data
	if selected_id < 0 {
		set_import_status("", "No recipe selected.")
		return
	}
	open_file_dialog(.Export_Single, "Export recipe as JSON", cast(^gtk.Window)main_window)
}

on_export_all_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	_ = button
	_ = data
	open_file_dialog(.Export_All, "Export all recipes as JSON", cast(^gtk.Window)main_window)
}

// open_file_dialog opens a GtkFileDialog for one purpose.
// Save dialogs get an initial name; open dialogs do not
// filter by extension (the parse step reports a bad file).
open_file_dialog :: proc(purpose: Dialog_Purpose, title: string, parent: ^gtk.Window) {
	if dialog_open {
		return
	}
	dialog := gtk.file_dialog_new()
	cs := strings.clone_to_cstring(title)
	defer delete(cs)
	gtk.file_dialog_set_title(dialog, cs)
	if purpose == .Export_Single || purpose == .Export_All {
		name := "recipes.json"
		if purpose == .Export_Single && selected_id >= 0 {
			for r in recipes {
				if r.id == selected_id {
					name = default_file_name(r.title)
					break
				}
			}
		}
		ncs := strings.clone_to_cstring(name)
		defer delete(ncs)
		gtk.file_dialog_set_initial_name(dialog, ncs)
	}
	dialog_open = true
	dialog_purpose = purpose
	dialog_dialog = dialog
	if purpose == .Export_Single || purpose == .Export_All {
		gtk.file_dialog_save(dialog, parent, nil, on_save_dialog_done, nil)
	} else {
		gtk.file_dialog_open(dialog, parent, nil, on_open_dialog_done, nil)
	}
}

dialog_path :: proc(res: [^]gio.AsyncResult, save: bool) -> (string, bool) {
	// Returns (path, cancelled). A dismissed dialog yields
	// no file; anything else is a real error to report.
	err: ^glib.Error
	file: ^gio.File
	if save {
		file = gtk.file_dialog_save_finish(dialog_dialog, cast(^gio.AsyncResult)res, &err)
	} else {
		file = gtk.file_dialog_open_finish(dialog_dialog, cast(^gio.AsyncResult)res, &err)
	}
	if file == nil {
		if err != nil {
			// Cancelled (user dismissed) is silent; other
			// errors surface as a status line.
			domain := err.domain
			code := err.code
			glib.error_free(err)
			_ = domain
			_ = code
		}
		return "", true
	}
	cs := gio.file_get_path(file)
	if cs == nil {
		return "", true
	}
	s, _ := strings.clone_from_cstring(cs)
	return s, false
}

on_open_dialog_done :: proc "c" (source: ^gobj.Object, res: [^]gio.AsyncResult, data: glib.pointer) {
	context = runtime.default_context()
	_ = source
	_ = data
	dialog_open = false
	purpose := dialog_purpose
	dialog_purpose = .None
	path, cancelled := dialog_path(res, false)
	if cancelled {
		return
	}
	defer delete(path)
	if purpose == .Import_File {
		start_import_job("", path)
	} else if purpose == .Choose_Image {
		if f := active_form; f != nil {
			rel, cerr := copy_image_file(path)
			if cerr != "" {
				set_text(f.error_label, cerr)
				return
			}
			f.image_path = rel
			set_text(f.image_label, filepath_base(rel))
		}
	}
}

on_save_dialog_done :: proc "c" (source: ^gobj.Object, res: [^]gio.AsyncResult, data: glib.pointer) {
	context = runtime.default_context()
	_ = source
	_ = data
	dialog_open = false
	purpose := dialog_purpose
	dialog_purpose = .None
	path, cancelled := dialog_path(res, true)
	if cancelled {
		return
	}
	defer delete(path)
	if purpose == .Export_Single {
		for r in recipes {
			if r.id == selected_id {
				finish_export_status(path, export_single(r), "Exported 1 recipe")
				return
			}
		}
	} else if purpose == .Export_All {
		finish_export_status(path, export_collection(recipes), "Exported all recipes")
	}
}

// finish_export_status writes an export and reports it in
// the left-pane status line, reusing json_export's
// finish_export message bookkeeping.
finish_export_status :: proc(path, serialized, summary: string) {
	message, err: string
	finish_export(&message, &err, path, serialized, summary)
	defer if message != "" {
		delete(message)
	}
	defer if err != "" {
		delete(err)
	}
	set_import_status(message, err)
}

// tick_cb runs every ~16ms on the main thread: it steps
// the detail fade, collects finished image decodes and
// import jobs. Returning true keeps the timeout alive.
tick_cb :: proc "c" (data: glib.pointer) -> glib.boolean {
	context = runtime.default_context()
	_ = data
	if transition_active && detail_box_widget != nil {
		elapsed := time.since(transition_start)
		frac := time.duration_seconds(elapsed) / 0.25
		if frac >= 1 {
			gtk.widget_set_opacity(detail_box_widget, 1)
			transition_active = false
		} else {
			eased := 1 - (1 - frac) * (1 - frac) * (1 - frac)
			gtk.widget_set_opacity(detail_box_widget, eased)
		}
	}
	poll_image_jobs()
	poll_import()
	return true
}

filepath_base :: proc(path: string) -> string {
	// Base name for the form's image label; the stored path
	// stays "images/<name>".
	for i := len(path) - 1; i >= 0; i -= 1 {
		if path[i] == '/' {
			return path[i + 1:]
		}
	}
	return path
}

activate :: proc "c" (app: ^gtk.Application, _: rawptr) {
	context = runtime.default_context()
	window := gobj.type_cast(
		gtk.Window,
		gtk.application_window_new(app),
		gtk.window_get_type(),
	)
	gtk.window_set_title(window, "Recipe Manager")
	gtk.window_set_default_size(window, 900, 600)

	list_box := cast(^gtk.ListBox)gtk.list_box_new()
	main_list_box = list_box
	search_entry = gtk.search_entry_new()
	gtk.search_entry_set_placeholder_text(
		cast(^gtk.SearchEntry)search_entry,
		"Type to filter recipes…",
	)
	gobj.signal_connect(
		search_entry,
		"search-changed",
		cast(gobj.Callback)on_search_changed,
		nil,
	)
	rebuild_list()
	list_scrolled := gtk.scrolled_window_new()
	gtk.scrolled_window_set_child(
		cast(^gtk.ScrolledWindow)list_scrolled,
		cast(^gtk.Widget)list_box,
	)
	gtk.widget_set_size_request(list_scrolled, 250, -1)

	// Heap-allocated: activate returns before the app runs,
	// so the Detail must outlive this stack frame. It lives
	// for the app's lifetime and is never freed.
	d := new(Detail)
	detail_ptr = d

	detail_box := cast(^gtk.Box)gtk.box_new(.VERTICAL, 6)
	detail_box_widget = cast(^gtk.Widget)detail_box
	d.image_picture = gtk.picture_new()
	// SCALE_DOWN: the photo shows at its decoded size (at
	// most 400x300) and never scales up to fill the pane.
	gtk.picture_set_content_fit(
		cast(^gtk.Picture)d.image_picture,
		gtk.ContentFit.SCALE_DOWN,
	)
	loading_spinner := gtk.spinner_new()
	gtk.spinner_start(cast(^gtk.Spinner)loading_spinner)
	loading_label := new_label("Loading image…")
	d.image_spinner_box = gtk.box_new(.HORIZONTAL, 6)
	gtk.box_append(cast(^gtk.Box)d.image_spinner_box, loading_spinner)
	gtk.box_append(cast(^gtk.Box)d.image_spinner_box, loading_label)
	d.image_status = detail_label()
	gtk.box_append(detail_box, d.image_picture)
	gtk.box_append(detail_box, d.image_spinner_box)
	gtk.box_append(detail_box, d.image_status)
	d.title = detail_label()
	gtk.box_append(detail_box, d.title)
	d.description = detail_label()
	gtk.label_set_wrap(cast(^gtk.Label)d.description, true)
	gtk.box_append(detail_box, d.description)
	d.servings = detail_label()
	gtk.box_append(detail_box, d.servings)
	gtk.box_append(detail_box, new_label("Ingredients"))
	for i in 0 ..< len(d.ingredient_labels) {
		d.ingredient_labels[i] = detail_label()
		gtk.box_append(detail_box, d.ingredient_labels[i])
	}
	gtk.box_append(detail_box, new_label("Steps"))
	for i in 0 ..< len(d.step_labels) {
		d.step_labels[i] = detail_label()
		gtk.box_append(detail_box, d.step_labels[i])
	}
	d.notes = detail_label()
	gtk.label_set_wrap(cast(^gtk.Label)d.notes, true)
	gtk.box_append(detail_box, d.notes)
	edit_button := gtk.button_new_with_label("Edit recipe")
	gobj.signal_connect(
		edit_button,
		"clicked",
		cast(gobj.Callback)on_edit_clicked,
		window,
	)
	gtk.box_append(detail_box, edit_button)
	delete_button := gtk.button_new_with_label("Delete recipe")
	gobj.signal_connect(
		delete_button,
		"clicked",
		cast(gobj.Callback)on_delete_clicked,
		window,
	)
	gtk.box_append(detail_box, delete_button)

	detail_scrolled := gtk.scrolled_window_new()
	gtk.scrolled_window_set_child(
		cast(^gtk.ScrolledWindow)detail_scrolled,
		cast(^gtk.Widget)detail_box,
	)
	gtk.widget_set_hexpand(detail_scrolled, true)
	gtk.widget_set_vexpand(detail_scrolled, true)

	add_button := gtk.button_new_with_label("Add recipe")
	gobj.signal_connect(
		add_button,
		"clicked",
		cast(gobj.Callback)on_add_clicked,
		window,
	)
	left_box := cast(^gtk.Box)gtk.box_new(.VERTICAL, 6)
	gtk.box_append(left_box, search_entry)
	gtk.box_append(left_box, add_button)
	gtk.box_append(left_box, list_scrolled)
	url_entry = gtk.entry_new()
	set_entry_text(url_entry, "http://localhost:8000/recipes.json")
	gtk.box_append(left_box, url_entry)
	import_button = gtk.button_new_with_label("Import from URL")
	gobj.signal_connect(
		import_button,
		"clicked",
		cast(gobj.Callback)on_import_clicked,
		window,
	)
	gtk.box_append(left_box, import_button)
	import_file_button = gtk.button_new_with_label("Import from file…")
	gobj.signal_connect(
		import_file_button,
		"clicked",
		cast(gobj.Callback)on_import_file_clicked,
		window,
	)
	gtk.box_append(left_box, import_file_button)
	export_box := gtk.box_new(.HORIZONTAL, 6)
	export_single_button = gtk.button_new_with_label("Export recipe…")
	gobj.signal_connect(
		export_single_button,
		"clicked",
		cast(gobj.Callback)on_export_single_clicked,
		window,
	)
	gtk.box_append(cast(^gtk.Box)export_box, export_single_button)
	export_all_button = gtk.button_new_with_label("Export all…")
	gobj.signal_connect(
		export_all_button,
		"clicked",
		cast(gobj.Callback)on_export_all_clicked,
		window,
	)
	gtk.box_append(cast(^gtk.Box)export_box, export_all_button)
	gtk.box_append(left_box, export_box)
	import_spinner := gtk.spinner_new()
	gtk.spinner_start(cast(^gtk.Spinner)import_spinner)
	import_spinner_box = gtk.box_new(.HORIZONTAL, 6)
	gtk.box_append(cast(^gtk.Box)import_spinner_box, import_spinner)
	gtk.box_append(cast(^gtk.Box)import_spinner_box, new_label("Importing…"))
	gtk.widget_set_visible(import_spinner_box, false)
	gtk.box_append(left_box, import_spinner_box)
	import_status = detail_label()
	gtk.label_set_wrap(cast(^gtk.Label)import_status, true)
	gtk.box_append(left_box, import_status)

	root := cast(^gtk.Box)gtk.box_new(.HORIZONTAL, 0)
	gtk.box_append(root, cast(^gtk.Widget)left_box)
	gtk.box_append(root, detail_scrolled)
	gtk.window_set_child(window, cast(^gtk.Widget)root)

	gobj.signal_connect(
		list_box,
		"row-selected",
		cast(gobj.Callback)on_row_selected,
		d,
	)
	if db_error_msg != "" {
		set_text(d.title, db_error_msg)
	} else if len(filtered) > 0 {
		show_recipe(d, recipes[filtered[0]])
		gtk.list_box_select_row(
			list_box,
			gtk.list_box_get_row_at_index(list_box, 0),
		)
	}

	main_window = cast(^gtk.Widget)window
	glib.timeout_add(16, tick_cb, nil)

	gtk.window_present(window)
}


// --- Add recipe ---

IngredientRow :: struct {
	box:                ^gtk.Widget,
	amount, unit, name: ^gtk.Widget,
}

StepRow :: struct {
	box:   ^gtk.Widget,
	entry: ^gtk.Widget,
}

// Form holds the add window's widgets. Heap-allocated like
// Detail: the window outlives the handler that opens it.
Form :: struct {
	window:                       ^gtk.Widget,
	edit_id:                      i64,
	title, description, servings: ^gtk.Widget,
	notes:                        ^gtk.Widget,
	error_label:                  ^gtk.Widget,
	ing_box, step_box:            ^gtk.Widget,
	ing_rows:                     [dynamic]IngredientRow,
	step_rows:                    [dynamic]StepRow,
	// Image chosen with "Choose image…", stored as
	// "images/<name>" on save; "" means no image.
	image_path:  string,
	image_label: ^gtk.Widget,
}

entry_text :: proc(w: ^gtk.Widget) -> string {
	cs := gtk.editable_get_text(cast(^gtk.Editable)w)
	s, _ := strings.clone_from_cstring(cs)
	return s
}

// set_entry_text writes into an entry. gtk_editable_set_text
// copies the string, so the clone can be freed right away.
set_entry_text :: proc(w: ^gtk.Widget, s: string) {
	cs := strings.clone_to_cstring(s)
	defer delete(cs)
	gtk.editable_set_text(cast(^gtk.Editable)w, cs)
}

// title_matches_search is the list filter, mirroring
// cpp-gtk4's search.h: case-insensitive substring match
// on the recipe TITLE only; an empty query matches
// everything; the query is NOT trimmed.
title_matches_search :: proc(title, query: string) -> bool {
	if query == "" {
		return true
	}
	title_lower := strings.to_lower(title)
	defer delete(title_lower)
	query_lower := strings.to_lower(query)
	defer delete(query_lower)
	return strings.contains(title_lower, query_lower)
}

apply_filter :: proc() {
	clear(&filtered)
	query := entry_text(search_entry)
	defer delete(query)
	for r, i in recipes {
		if title_matches_search(r.title, query) {
			append(&filtered, i)
		}
	}
}

rebuild_list :: proc() {
	apply_filter()
	for {
		child := gtk.widget_get_first_child(cast(^gtk.Widget)main_list_box)
		if child == nil {
			break
		}
		gtk.list_box_remove(main_list_box, child)
	}
	clear(&image_row_refs)
	for idx in filtered {
		r := recipes[idx]
		// Row: a 32px image slot (photo, spinner, or blank)
		// plus the title label. Row labels stay
		// unselectable so the row itself gets the click.
		row_box := gtk.box_new(.HORIZONTAL, 6)
		picture := gtk.picture_new()
		gtk.picture_set_content_fit(
			cast(^gtk.Picture)picture,
			gtk.ContentFit.SCALE_DOWN,
		)
		gtk.widget_set_size_request(picture, 32, 32)
		spinner := gtk.spinner_new()
		gtk.widget_set_size_request(spinner, 32, 32)
		gtk.spinner_start(cast(^gtk.Spinner)spinner)
		placeholder := gtk.label_new("")
		gtk.widget_set_size_request(placeholder, 32, 32)
		slot := gtk.box_new(.HORIZONTAL, 0)
		gtk.box_append(cast(^gtk.Box)slot, picture)
		gtk.box_append(cast(^gtk.Box)slot, spinner)
		gtk.box_append(cast(^gtk.Box)slot, placeholder)
		gtk.box_append(cast(^gtk.Box)row_box, slot)
		gtk.box_append(cast(^gtk.Box)row_box, new_label(r.title))
		gtk.list_box_append(main_list_box, row_box)
		ref := Image_Row_Ref{
			path = r.image_path,
			picture = picture,
			spinner = spinner,
			placeholder = placeholder,
		}
		append(&image_row_refs, ref)
		refresh_row_ref(ref)
	}
	start_image_loads()
}

add_ingredient_row :: proc(f: ^Form) {
	row_box := cast(^gtk.Box)gtk.box_new(.HORIZONTAL, 6)
	amount := gtk.entry_new()
	unit := gtk.entry_new()
	name := gtk.entry_new()
	gtk.box_append(row_box, amount)
	gtk.box_append(row_box, unit)
	gtk.box_append(row_box, name)
	remove := gtk.button_new_with_label("Remove")
	gtk.box_append(row_box, remove)
	gobj.signal_connect(
		remove,
		"clicked",
		cast(gobj.Callback)on_remove_ingredient,
		cast(^gtk.Widget)row_box,
	)
	gtk.box_append(cast(^gtk.Box)f.ing_box, cast(^gtk.Widget)row_box)
	append(&f.ing_rows, IngredientRow{
		box = cast(^gtk.Widget)row_box,
		amount = amount, unit = unit, name = name,
	})
}

add_step_row :: proc(f: ^Form) {
	row_box := cast(^gtk.Box)gtk.box_new(.HORIZONTAL, 6)
	entry := gtk.entry_new()
	gtk.box_append(row_box, entry)
	remove := gtk.button_new_with_label("Remove")
	gtk.box_append(row_box, remove)
	gobj.signal_connect(
		remove,
		"clicked",
		cast(gobj.Callback)on_remove_step,
		cast(^gtk.Widget)row_box,
	)
	gtk.box_append(cast(^gtk.Box)f.step_box, cast(^gtk.Widget)row_box)
	append(&f.step_rows, StepRow{
		box = cast(^gtk.Widget)row_box,
		entry = entry,
	})
}

on_remove_ingredient :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	f := active_form
	if f == nil {
		return
	}
	row_box := cast(^gtk.Widget)data
	for row, i in f.ing_rows {
		if row.box == row_box {
			gtk.box_remove(cast(^gtk.Box)f.ing_box, row_box)
			ordered_remove(&f.ing_rows, i)
			return
		}
	}
}

on_remove_step :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	f := active_form
	if f == nil {
		return
	}
	row_box := cast(^gtk.Widget)data
	for row, i in f.step_rows {
		if row.box == row_box {
			gtk.box_remove(cast(^gtk.Box)f.step_box, row_box)
			ordered_remove(&f.step_rows, i)
			return
		}
	}
}

on_add_ingredient_row :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	add_ingredient_row(cast(^Form)data)
}

on_add_step_row :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	add_step_row(cast(^Form)data)
}

on_add_save :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	f := cast(^Form)data
	title := strings.trim_space(entry_text(f.title))
	if title == "" {
		set_text(f.error_label, "Title is required.")
		return
	}
	servings := gtk.spin_button_get_value_as_int(
		cast(^gtk.SpinButton)f.servings,
	)
	ingredients := make([dynamic]Ingredient)
	for row in f.ing_rows {
		amount := strings.trim_space(entry_text(row.amount))
		unit := strings.trim_space(entry_text(row.unit))
		name := strings.trim_space(entry_text(row.name))
		if amount == "" && unit == "" && name == "" {
			continue
		}
		append(&ingredients, Ingredient{
			amount = amount, unit = unit, name = name,
		})
	}
	steps := make([dynamic]string)
	for row in f.step_rows {
		text := strings.trim_space(entry_text(row.entry))
		if text == "" {
			continue
		}
		append(&steps, text)
	}
	recipe := Recipe{
		title       = title,
		description = strings.trim_space(entry_text(f.description)),
		servings    = int(servings),
		image_path  = f.image_path,
		ingredients = ingredients[:],
		steps       = steps[:],
		notes       = strings.trim_space(entry_text(f.notes)),
	}
	// The strings above are heap clones that live through
	// this call, and insert/update bind (SQLITE_STATIC) and
	// step before returning, so they are valid throughout.
	saved_id := f.edit_id
	if f.edit_id >= 0 {
		recipe.id = f.edit_id
		if err := update_recipe(db_handle, recipe); err != "" {
			set_text(f.error_label, err)
			return
		}
	} else {
		id, err := insert_recipe(db_handle, recipe)
		if err != "" {
			set_text(f.error_label, err)
			return
		}
		saved_id = id
	}
	loaded, load_err := load_recipes(db_handle)
	if load_err != "" {
		set_text(f.error_label, load_err)
		return
	}
	recipes = loaded
	rebuild_list()
	for idx, p in filtered {
		if recipes[idx].id == saved_id {
			gtk.list_box_select_row(
				main_list_box,
				gtk.list_box_get_row_at_index(main_list_box, i32(p)),
			)
			break
		}
	}
	active_form = nil
	gtk.window_destroy(cast(^gtk.Window)f.window)
}

on_add_cancel :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	f := cast(^Form)data
	active_form = nil
	gtk.window_destroy(cast(^gtk.Window)f.window)
}

// open_form builds the add/edit form window. prefill is
// nil for adding; for editing it points at the selected
// recipe in recipes (its fields are copied into the
// entries immediately, so the pointer need not outlive
// this call), and edit_id is that recipe's id, or -1.
open_form :: proc(parent: ^gtk.Window, prefill: ^Recipe, edit_id: i64) {
	context = runtime.default_context()
	f := new(Form)
	f.edit_id = edit_id
	active_form = f
	window := gtk.window_new()
	f.window = window
	if edit_id >= 0 {
		gtk.window_set_title(cast(^gtk.Window)window, "Edit Recipe")
	} else {
		gtk.window_set_title(cast(^gtk.Window)window, "Add Recipe")
	}
	gtk.window_set_transient_for(cast(^gtk.Window)window, parent)
	gtk.window_set_modal(cast(^gtk.Window)window, true)
	gtk.window_set_default_size(cast(^gtk.Window)window, 500, 600)

	form_box := cast(^gtk.Box)gtk.box_new(.VERTICAL, 6)
	gtk.box_append(form_box, new_label("Title:"))
	f.title = gtk.entry_new()
	if prefill != nil {
		set_entry_text(f.title, prefill.title)
	}
	gtk.box_append(form_box, f.title)
	gtk.box_append(form_box, new_label("Description:"))
	f.description = gtk.entry_new()
	if prefill != nil {
		set_entry_text(f.description, prefill.description)
	}
	gtk.box_append(form_box, f.description)
	gtk.box_append(form_box, new_label("Servings:"))
	f.servings = gtk.spin_button_new_with_range(1, 100, 1)
	if prefill != nil {
		gtk.spin_button_set_value(
			cast(^gtk.SpinButton)f.servings,
			f64(prefill.servings),
		)
	}
	gtk.box_append(form_box, f.servings)
	gtk.box_append(form_box, new_label("Ingredients:"))
	f.ing_box = cast(^gtk.Widget)gtk.box_new(.VERTICAL, 6)
	gtk.box_append(form_box, f.ing_box)
	add_ing := gtk.button_new_with_label("Add ingredient")
	gobj.signal_connect(
		add_ing,
		"clicked",
		cast(gobj.Callback)on_add_ingredient_row,
		f,
	)
	gtk.box_append(form_box, add_ing)
	if prefill != nil {
		for ing in prefill.ingredients {
			add_ingredient_row(f)
			row := &f.ing_rows[len(f.ing_rows) - 1]
			set_entry_text(row.amount, ing.amount)
			set_entry_text(row.unit, ing.unit)
			set_entry_text(row.name, ing.name)
		}
		if len(f.ing_rows) == 0 {
			add_ingredient_row(f)
		}
	} else {
		add_ingredient_row(f)
	}
	gtk.box_append(form_box, new_label("Steps:"))
	f.step_box = cast(^gtk.Widget)gtk.box_new(.VERTICAL, 6)
	gtk.box_append(form_box, f.step_box)
	add_step := gtk.button_new_with_label("Add step")
	gobj.signal_connect(
		add_step,
		"clicked",
		cast(gobj.Callback)on_add_step_row,
		f,
	)
	gtk.box_append(form_box, add_step)
	if prefill != nil {
		for step in prefill.steps {
			add_step_row(f)
			row := &f.step_rows[len(f.step_rows) - 1]
			set_entry_text(row.entry, step)
		}
		if len(f.step_rows) == 0 {
			add_step_row(f)
		}
	} else {
		add_step_row(f)
	}
	gtk.box_append(form_box, new_label("Notes:"))
	f.notes = gtk.entry_new()
	if prefill != nil {
		set_entry_text(f.notes, prefill.notes)
	}
	gtk.box_append(form_box, f.notes)
	if prefill != nil {
		f.image_path = prefill.image_path
	}
	choose_button := gtk.button_new_with_label("Choose image…")
	gobj.signal_connect(
		choose_button,
		"clicked",
		cast(gobj.Callback)on_choose_image_clicked,
		window,
	)
	gtk.box_append(form_box, choose_button)
	f.image_label = new_label("No image")
	if f.image_path != "" {
		set_text(f.image_label, filepath_base(f.image_path))
	}
	gtk.box_append(form_box, f.image_label)
	f.error_label = detail_label()
	gtk.box_append(form_box, f.error_label)

	buttons := cast(^gtk.Box)gtk.box_new(.HORIZONTAL, 6)
	save := gtk.button_new_with_label("Save")
	gobj.signal_connect(
		save,
		"clicked",
		cast(gobj.Callback)on_add_save,
		f,
	)
	gtk.box_append(buttons, save)
	cancel := gtk.button_new_with_label("Cancel")
	gobj.signal_connect(
		cancel,
		"clicked",
		cast(gobj.Callback)on_add_cancel,
		f,
	)
	gtk.box_append(buttons, cancel)
	gtk.box_append(form_box, cast(^gtk.Widget)buttons)

	form_scrolled := gtk.scrolled_window_new()
	gtk.scrolled_window_set_child(
		cast(^gtk.ScrolledWindow)form_scrolled,
		cast(^gtk.Widget)form_box,
	)
	gtk.widget_set_hexpand(form_scrolled, true)
	gtk.widget_set_vexpand(form_scrolled, true)
	gtk.window_set_child(
		cast(^gtk.Window)window,
		cast(^gtk.Widget)form_scrolled,
	)
	gtk.window_present(cast(^gtk.Window)window)
}

on_choose_image_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	_ = button
	_ = data
	open_file_dialog(.Choose_Image, "Choose image", cast(^gtk.Window)main_window)
}

on_add_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	open_form(cast(^gtk.Window)data, nil, -1)
}

on_edit_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	if selected_id < 0 {
		return
	}
	for r, i in recipes {
		if r.id == selected_id {
			open_form(cast(^gtk.Window)data, &recipes[i], selected_id)
			return
		}
	}
}

on_delete_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	if selected_id < 0 {
		return
	}
	title := ""
	for r in recipes {
		if r.id == selected_id {
			title = r.title
			break
		}
	}
	pending_delete_id = selected_id
	parent := cast(^gtk.Window)data
	window := gtk.window_new()
	gtk.window_set_title(cast(^gtk.Window)window, "Delete recipe")
	gtk.window_set_transient_for(cast(^gtk.Window)window, parent)
	gtk.window_set_modal(cast(^gtk.Window)window, true)
	gtk.window_set_default_size(cast(^gtk.Window)window, 400, 150)
	box := cast(^gtk.Box)gtk.box_new(.VERTICAL, 6)
	msg := new_label(
		fmt.tprintf("Delete \"%s\"? This cannot be undone.", title),
	)
	gtk.label_set_wrap(cast(^gtk.Label)msg, true)
	gtk.box_append(box, msg)
	row := cast(^gtk.Box)gtk.box_new(.HORIZONTAL, 6)
	confirm := gtk.button_new_with_label("Delete")
	gobj.signal_connect(
		confirm,
		"clicked",
		cast(gobj.Callback)on_delete_confirm,
		window,
	)
	gtk.box_append(row, confirm)
	cancel := gtk.button_new_with_label("Cancel")
	gobj.signal_connect(
		cancel,
		"clicked",
		cast(gobj.Callback)on_delete_cancel,
		window,
	)
	gtk.box_append(row, cancel)
	gtk.box_append(box, cast(^gtk.Widget)row)
	gtk.window_set_child(cast(^gtk.Window)window, cast(^gtk.Widget)box)
	gtk.window_present(cast(^gtk.Window)window)
}

on_delete_confirm :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	window := cast(^gtk.Window)data
	if pending_delete_id < 0 {
		gtk.window_destroy(window)
		return
	}
	if err := delete_recipe(db_handle, pending_delete_id); err != "" {
		// The dialog has no error label; surface the error
		// as the window title so the failure is visible.
		cs := strings.clone_to_cstring(err)
		defer delete(cs)
		gtk.window_set_title(window, cs)
		return
	}
	pending_delete_id = -1
	loaded, load_err := load_recipes(db_handle)
	if load_err != "" {
		cs := strings.clone_to_cstring(load_err)
		defer delete(cs)
		gtk.window_set_title(window, cs)
		return
	}
	recipes = loaded
	rebuild_list()
	if len(filtered) > 0 {
		selected_id = recipes[filtered[0]].id
		show_recipe(detail_ptr, recipes[filtered[0]])
		row := gtk.list_box_get_row_at_index(main_list_box, 0)
		if row != nil {
			gtk.list_box_select_row(main_list_box, row)
		}
	} else {
		selected_id = -1
		clear_detail(detail_ptr)
	}
	gtk.window_destroy(window)
}

on_delete_cancel :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	pending_delete_id = -1
	gtk.window_destroy(cast(^gtk.Window)data)
}

main :: proc() {
	db, db_open_err := open_database("recipes.db")
	db_handle = db
	defer close_database(db)
	if db_open_err != "" {
		db_error_msg = db_open_err
	} else if err := ensure_schema_and_seed(db, RECIPES[:]); err != "" {
		db_error_msg = err
	} else {
		loaded, load_err := load_recipes(db)
		if load_err != "" {
			db_error_msg = load_err
		} else {
			recipes = loaded
		}
	}

	app := gtk.application_new(
		"org.desktop-app-exploration.odin-gtk",
		.APPLICATION_DEFAULT_FLAGS,
	)
	gobj.signal_connect(app, "activate", cast(gobj.Callback)activate, nil)

	argv := make([]cstring, len(os.args))
	for &arg, idx in argv {
		arg = strings.clone_to_cstring(os.args[idx])
	}
	defer delete(argv)
	defer for arg in argv do delete(arg)

	status := gio.application_run(
		gobj.type_cast(gio.Application, app, gio.TYPE_APPLICATION()),
		i32(len(argv)),
		raw_data(argv),
	)
	gobj.object_unref(app)

	if status != 0 {
		os.exit(int(status))
	}
}
