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
active_form: ^Form

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

on_row_selected :: proc "c" (box: ^gtk.ListBox, row: ^gtk.ListBoxRow, data: rawptr) {
	context = runtime.default_context()
	if row == nil {
		return
	}
	index := gtk.list_box_row_get_index(row)
	if index < 0 || int(index) >= len(recipes) {
		return
	}
	show_recipe(cast(^Detail)data, recipes[index])
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
	for r in recipes {
		gtk.list_box_append(list_box, new_label(r.title))
	}
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
	} else if len(recipes) > 0 {
		show_recipe(d, recipes[0])
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

rebuild_list :: proc() {
	for {
		child := gtk.widget_get_first_child(cast(^gtk.Widget)main_list_box)
		if child == nil {
			break
		}
		gtk.list_box_remove(main_list_box, child)
	}
	for r in recipes {
		gtk.list_box_append(main_list_box, new_label(r.title))
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
	// this call, and insert binds (SQLITE_STATIC) and steps
	// before returning, so they are valid throughout.
	id, err := insert_recipe(db_handle, recipe)
	if err != "" {
		set_text(f.error_label, err)
		return
	}
	loaded, load_err := load_recipes(db_handle)
	if load_err != "" {
		set_text(f.error_label, load_err)
		return
	}
	recipes = loaded
	rebuild_list()
	for r, i in recipes {
		if r.id == id {
			gtk.list_box_select_row(
				main_list_box,
				gtk.list_box_get_row_at_index(main_list_box, i32(i)),
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

on_add_clicked :: proc "c" (button: ^gtk.Widget, data: rawptr) {
	context = runtime.default_context()
	parent := cast(^gtk.Window)data
	f := new(Form)
	active_form = f
	window := gtk.window_new()
	f.window = window
	gtk.window_set_title(cast(^gtk.Window)window, "Add Recipe")
	gtk.window_set_transient_for(cast(^gtk.Window)window, parent)
	gtk.window_set_modal(cast(^gtk.Window)window, true)
	gtk.window_set_default_size(cast(^gtk.Window)window, 500, 600)

	form_box := cast(^gtk.Box)gtk.box_new(.VERTICAL, 6)
	gtk.box_append(form_box, new_label("Title:"))
	f.title = gtk.entry_new()
	gtk.box_append(form_box, f.title)
	gtk.box_append(form_box, new_label("Description:"))
	f.description = gtk.entry_new()
	gtk.box_append(form_box, f.description)
	gtk.box_append(form_box, new_label("Servings:"))
	f.servings = gtk.spin_button_new_with_range(1, 100, 1)
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
	add_ingredient_row(f)
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
	add_step_row(f)
	gtk.box_append(form_box, new_label("Notes:"))
	f.notes = gtk.entry_new()
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
