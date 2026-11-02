package main

// Recipe list and detail view, hard-coded data: the same 3
// recipes the other stacks start with (Banana Bread, Tomato
// Basil Pasta, Chicken Stir Fry). The list is a GtkListBox;
// selecting a row fills the detail pane on the right.
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

Ingredient :: struct {
	quantity, unit, name: string,
}

Recipe :: struct {
	title, description: string,
	servings:    int,
	ingredients: []Ingredient,
	steps:       []string,
	notes:       string,
}

RECIPES := []Recipe{
	{
		"Banana Bread",
		"A classic loaf, best with very ripe bananas.",
		8,
		[]Ingredient{
			{"3", "", "ripe bananas, mashed"},
			{"1/2", "cup", "butter, melted"},
			{"3/4", "cup", "sugar"},
			{"1", "", "egg"},
			{"1", "tsp", "vanilla"},
			{"1", "tsp", "baking soda"},
			{"1 1/2", "cups", "flour"},
		},
		[]string{
			"Preheat the oven to 350°F and grease a 9x5 loaf pan.",
			"Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.",
			"Stir in the baking soda and flour until just combined.",
			"Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.",
			"Cool in the pan for 10 minutes, then turn out onto a rack.",
		},
		"Optional: fold in walnuts or chocolate chips before baking.",
	},
	{
		"Tomato Basil Pasta",
		"A quick weeknight pasta with fresh tomatoes and basil.",
		4,
		[]Ingredient{
			{"12", "oz", "pasta"},
			{"2", "lbs", "tomatoes, chopped"},
			{"3", "cloves", "garlic, sliced"},
			{"1/4", "cup", "olive oil"},
			{"1", "cup", "basil leaves"},
			{"1/2", "cup", "parmesan, grated"},
		},
		[]string{
			"Cook the pasta in salted water until al dente, reserving a cup of pasta water.",
			"Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.",
			"Add the tomatoes and cook until they soften, about 8 minutes.",
			"Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.",
		},
		"Serve immediately, with extra parmesan on top.",
	},
	{
		"Chicken Stir Fry",
		"Chicken and vegetables in a simple soy-ginger sauce, served with rice.",
		4,
		[]Ingredient{
			{"1 1/2", "lbs", "chicken breast, sliced"},
			{"2", "", "bell peppers, sliced"},
			{"2", "cups", "broccoli florets"},
			{"3", "tbsp", "soy sauce"},
			{"1", "tbsp", "ginger, grated"},
			{"2", "cloves", "garlic, minced"},
		},
		[]string{
			"Sear the chicken in a hot, oiled pan until cooked through, then set aside.",
			"Stir fry the peppers and broccoli until just tender, about 4 minutes.",
			"Return the chicken to the pan with the soy sauce, ginger, and garlic.",
			"Cook for 2 more minutes, stirring, until the sauce coats everything.",
		},
		"Serve over rice.",
	},
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
				line = fmt.tprintf("%s %s", ing.quantity, ing.name)
			} else {
				line = fmt.tprintf("%s %s %s", ing.quantity, ing.unit, ing.name)
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
	if index < 0 || int(index) >= len(RECIPES) {
		return
	}
	show_recipe(cast(^Detail)data, RECIPES[index])
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
	for r in RECIPES {
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

	root := cast(^gtk.Box)gtk.box_new(.HORIZONTAL, 0)
	gtk.box_append(root, list_scrolled)
	gtk.box_append(root, detail_scrolled)
	gtk.window_set_child(window, cast(^gtk.Widget)root)

	gobj.signal_connect(
		list_box,
		"row-selected",
		cast(gobj.Callback)on_row_selected,
		d,
	)
	show_recipe(d, RECIPES[0])
	gtk.list_box_select_row(
		list_box,
		gtk.list_box_get_row_at_index(list_box, 0),
	)

	gtk.window_present(window)
}

main :: proc() {
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
