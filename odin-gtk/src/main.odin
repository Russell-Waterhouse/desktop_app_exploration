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
// left-aligned like the list rows.
detail_label :: proc() -> ^gtk.Widget {
	w := gtk.label_new("")
	gtk.label_set_xalign(cast(^gtk.Label)w, 0)
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
	for idx in filtered {
		gtk.list_box_append(main_list_box, new_label(recipes[idx].title))
	}
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
