package main

// Hello world: a GTK4 window, via the odin-gtk bindings.
// The bindings are fetched by install_ubuntu.sh / install_fedora.sh
// into third_party/odin-gtk (pinned to tag 4.17.2) and imported
// by relative path, the way the bindings' own examples do it.
// The code follows the bindings' 4.17.2 example idiom: windows
// are built in the activate handler, signal handlers are passed
// as cast(gobj.Callback), and the application is run through a
// gobj.type_cast to gio.Application.

import "core:os"
import "core:strings"
import gio "../third_party/odin-gtk/glib/gio"
import gobj "../third_party/odin-gtk/glib/gobject"
import gtk "../third_party/odin-gtk/gtk"

activate :: proc "c" (app: ^gtk.Application, _: rawptr) {
	window := gobj.type_cast(
		gtk.Window,
		gtk.application_window_new(app),
		gtk.window_get_type(),
	)
	gtk.window_set_title(window, "Recipe Manager")
	gtk.window_set_default_size(window, 900, 600)
	gtk.window_set_child(window, gtk.label_new("Hello, GTK4!"))

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
