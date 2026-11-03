#!/usr/bin/env python3
# UI tests for cpp-gtk4, driven through AT-SPI with dogtail.
#
# This is the black-box counterpart to the rust-egui egui_kittest
# tests: it launches the real cpp-gtk4 binary and drives its real
# windows, instead of linking the UI into the test process. There
# is no headless GTK equivalent of egui_kittest, so these tests
# need a display server and an accessibility bus. Run them from
# this directory, after building with ./build_linux.sh:
#
#   dbus-run-session xvfb-run -a python3 test_ui_dogtail.py
#
# Dependencies (see README.md): dogtail 2.x, python-xlib, and the
# at-spi2-core package for the accessibility bus. On Ubuntu:
#   sudo apt install at-spi2-core
#   pip install --user dogtail python-xlib
# (dogtail needs the python3-gi package for its gi bindings.)
#
# Each test launches a fresh app in its own temporary working
# directory, so the app seeds a fresh recipes.db there; the real
# recipes.db in the working directory is never opened. The app's
# GTK configuration is also pointed at a temporary directory
# (XDG_CONFIG_HOME) that disables window shadows, which dogtail
# documents as necessary for accurate GTK4 coordinate handling.
# The tests themselves avoid coordinates where AT-SPI offers a
# direct route: buttons are activated with do_action_named("click")
# and text is set through the editable-text interface, while list
# rows are selected through the list's Selection interface
# (select_child), because GtkListBox rows expose no click action.
# One coordinate-free exception is noted in test_list_selection:
# a pointer click on a row is the user-visible path, but dogtail
# coordinate clicks are sensitive to window placement under
# Xvfb, so selection is asserted through the Selection interface
# and the resulting detail pane instead.
#
# Exit code is 0 only when every test passes; unittest prints
# each failure and continues with the remaining tests.

import os
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from dogtail.tree import root

SCRIPT_DIR = Path(__file__).resolve().parent
BINARY = Path(os.environ.get("CPP_GTK4_BINARY", SCRIPT_DIR / "build" / "cpp-gtk4"))

SEED_TITLES = [
    "Banana Bread",
    "Tomato Basil Pasta",
    "Chicken Stir Fry",
    "كبسة الدجاج",
    "पालक पनीर",
    "番茄炒蛋",
    "🥞 Blueberry Pancakes 🫐",
]


def wait_until(condition, timeout=15, what="condition"):
    """Poll condition() until it returns a truthy value, re-querying
    the AT-SPI tree on every attempt (nodes go stale when the app
    rebuilds a pane or opens/closes a window). Returns the value;
    raises AssertionError with the last observed value on timeout."""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = condition()
            if last:
                return last
        except Exception as exc:  # tree nodes can die mid-query
            last = exc
        time.sleep(0.2)
    raise AssertionError(f"Timed out waiting for {what}; last: {last!r}")


def walk(node):
    """Yield node and all descendants, skipping dead subtrees."""
    yield node
    try:
        children = node.children
    except Exception:
        return
    for child in children:
        yield from walk(child)


def find_all(node, role_name=None, name=None):
    out = []
    for n in walk(node):
        try:
            if role_name is not None and n.role_name != role_name:
                continue
            if name is not None and n.name != name:
                continue
        except Exception:
            continue
        out.append(n)
    return out


def find_first(node, role_name=None, name=None):
    found = find_all(node, role_name, name)
    if not found:
        raise AssertionError(
            f"No node role={role_name!r} name={name!r} under {node.name!r}")
    return found[0]


def label_texts(node):
    return [n.text for n in find_all(node, role_name="label")]


def list_titles(main):
    """Titles in the recipe list, in list order."""
    lst = find_first(main, role_name="list")
    titles = []
    for row in lst.children:
        labels = [n.text for n in walk(row) if n.role_name == "label"]
        titles.append(labels[0] if labels else "")
    return titles


def detail_labels(main):
    """Labels in the detail pane: the scroll pane that contains the
    Edit/Delete buttons (the list pane contains no buttons)."""
    for pane in find_all(main, role_name="scroll pane"):
        buttons = [n.name for n in walk(pane)
                   if n.role_name == "push button"]
        if "Edit" in buttons:
            return label_texts(pane)
    raise AssertionError("Detail pane (scroll pane with Edit button) not found")


def form_text_nodes(form):
    """Editable text nodes in the add/edit form, in document order:
    title, description, then ingredient rows (amount, unit, name),
    then step rows, then notes."""
    return find_all(form, role_name="text")


def form_button(form, name):
    return find_first(form, role_name="push button", name=name)


class DogtailTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="cpp-gtk4-ui-test-")
        self.workdir = Path(self.tmp.name) / "work"
        self.workdir.mkdir()
        configdir = Path(self.tmp.name) / "config" / "gtk-4.0"
        configdir.mkdir(parents=True)
        # Window shadows must be disabled for GTK4 automation.
        (configdir / "gtk.css").write_text(
            "window, .popover, .tooltip {\n    box-shadow: none;\n}\n",
            encoding="utf-8")
        env = dict(os.environ)
        env["GTK_A11Y"] = "atspi"
        env["XDG_CONFIG_HOME"] = str(Path(self.tmp.name) / "config")
        self.proc = subprocess.Popen(
            [str(BINARY)], cwd=str(self.workdir), env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.app = wait_until(self._find_app, what="Recipe Manager window")

    def tearDown(self):
        try:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()
        self.tmp.cleanup()

    def _find_app(self):
        for app in root.applications():
            for window in app.children:
                if window.name == "Recipe Manager":
                    return app
        return None

    def main(self):
        return wait_until(
            lambda: find_first(self.app, role_name="frame",
                               name="Recipe Manager"),
            what="main frame")

    def db_titles(self):
        with sqlite3.connect(str(self.workdir / "recipes.db")) as conn:
            return [row[0] for row in
                    conn.execute("SELECT title FROM recipes ORDER BY id")]

    def db_recipe(self, title):
        with sqlite3.connect(str(self.workdir / "recipes.db")) as conn:
            row = conn.execute(
                "SELECT id, description, servings, notes FROM recipes "
                "WHERE title = ?", (title,)).fetchone()
            if row is None:
                return None
            rid, description, servings, notes = row
            ingredients = conn.execute(
                "SELECT amount, unit, name FROM ingredients "
                "WHERE recipe_id = ? ORDER BY position", (rid,)).fetchall()
            steps = [r[0] for r in conn.execute(
                "SELECT text FROM steps WHERE recipe_id = ? "
                "ORDER BY position", (rid,)).fetchall()]
            return {"description": description, "servings": servings,
                    "notes": notes, "ingredients": ingredients,
                    "steps": steps}

    def select_recipe(self, index):
        main = self.main()
        lst = find_first(main, role_name="list")
        lst.select_child(index)

    def test_list_selection_shows_recipe_detail(self):
        main = self.main()
        self.assertEqual(list_titles(main), SEED_TITLES)
        # The first recipe is selected at startup.
        self.assertIn("Banana Bread", detail_labels(main))
        self.assertIn("Servings: 8", detail_labels(main))
        self.select_recipe(2)
        labels = wait_until(
            lambda: detail_labels(self.main())
            if "Chicken Stir Fry" in detail_labels(self.main()) else None,
            what="detail pane for Chicken Stir Fry")
        self.assertIn("Chicken and vegetables in a simple soy-ginger sauce, "
                      "served with rice.", labels)
        self.assertIn("Servings: 4", labels)
        # The list itself is unchanged by selecting a row.
        self.assertEqual(list_titles(self.main()), SEED_TITLES)

    def test_search_filters_list(self):
        main = self.main()
        search = find_first(main, role_name="entry")
        search.text = "pasta"
        titles = wait_until(
            lambda: list_titles(self.main())
            if list_titles(self.main()) == ["Tomato Basil Pasta"] else None,
            what="list filtered to Tomato Basil Pasta")
        self.assertEqual(titles, ["Tomato Basil Pasta"])
        # Clearing the search restores the full list.
        search = find_first(self.main(), role_name="entry")
        search.text = ""
        wait_until(
            lambda: list_titles(self.main()) == SEED_TITLES or None,
            what="full list after clearing search")

    def test_add_recipe_via_form(self):
        main = self.main()
        find_first(main, role_name="push button",
                   name="Add recipe").do_action_named("click")
        form = wait_until(
            lambda: find_first(self.app, role_name="frame",
                               name="Add recipe"),
            what="Add recipe form")
        texts = form_text_nodes(form)
        self.assertEqual(len(texts), 3)  # title, description, notes
        texts[0].text = "Dogtail Soup"
        texts[1].text = "A soup added through the real form."
        form_button(form, "Add ingredient").do_action_named("click")
        texts = wait_until(
            lambda: form_text_nodes(form)
            if len(form_text_nodes(form)) == 6 else None,
            what="ingredient row in form")
        texts[2].text = "2"
        texts[3].text = "cups"
        texts[4].text = "stock"
        form_button(form, "Add step").do_action_named("click")
        texts = wait_until(
            lambda: form_text_nodes(form)
            if len(form_text_nodes(form)) == 7 else None,
            what="step row in form")
        texts[5].text = "Simmer until done."
        texts[6].text = "Serve hot."
        spin = find_first(form, role_name="spin button")
        spin.value = 3
        form_button(form, "Save").do_action_named("click")
        wait_until(
            lambda: "Dogtail Soup" in list_titles(self.main()) or None,
            what="Dogtail Soup in list after save")
        self.assertEqual(len(self.db_titles()), 8)
        recipe = self.db_recipe("Dogtail Soup")
        self.assertEqual(recipe["description"],
                         "A soup added through the real form.")
        self.assertEqual(recipe["servings"], 3)
        self.assertEqual(recipe["ingredients"], [("2", "cups", "stock")])
        self.assertEqual(recipe["steps"], ["Simmer until done."])
        self.assertEqual(recipe["notes"], "Serve hot.")

    def test_add_recipe_rejects_empty_title(self):
        main = self.main()
        find_first(main, role_name="push button",
                   name="Add recipe").do_action_named("click")
        form = wait_until(
            lambda: find_first(self.app, role_name="frame",
                               name="Add recipe"),
            what="Add recipe form")
        form_button(form, "Save").do_action_named("click")
        # The form stays open and reports the error; nothing is saved.
        wait_until(
            lambda: "Title is required." in label_texts(form) or None,
            what="Title is required error")
        self.assertEqual(self.db_titles(), SEED_TITLES)
        form_button(form, "Cancel").do_action_named("click")
        wait_until(
            lambda: not find_all(self.app, role_name="frame",
                                 name="Add recipe") or None,
            what="form closed after Cancel")

    def test_edit_recipe_changes_title(self):
        main = self.main()
        find_first(main, role_name="push button",
                   name="Edit").do_action_named("click")
        form = wait_until(
            lambda: find_first(self.app, role_name="frame",
                               name="Edit recipe"),
            what="Edit recipe form")
        title = form_text_nodes(form)[0]
        self.assertEqual(title.text, "Banana Bread")
        title.text = "Banana Bread (Edited)"
        form_button(form, "Save").do_action_named("click")
        wait_until(
            lambda: "Banana Bread (Edited)" in list_titles(self.main())
            or None,
            what="edited title in list")
        self.assertIn("Banana Bread (Edited)", self.db_titles())
        self.assertNotIn("Banana Bread", self.db_titles())
        # The rest of the recipe is unchanged.
        recipe = self.db_recipe("Banana Bread (Edited)")
        self.assertEqual(recipe["servings"], 8)
        self.assertEqual(len(recipe["ingredients"]), 7)

    def test_delete_recipe_removes_it(self):
        main = self.main()
        find_first(main, role_name="push button",
                   name="Delete").do_action_named("click")
        dialog = wait_until(
            lambda: find_first(self.app, role_name="frame",
                               name="Delete recipe"),
            what="Delete recipe dialog")
        self.assertIn("Delete “Banana Bread”?", label_texts(dialog))
        form_button(dialog, "Delete").do_action_named("click")
        wait_until(
            lambda: "Banana Bread" not in list_titles(self.main()) or None,
            what="Banana Bread removed from list")
        self.assertEqual(len(self.db_titles()), 6)
        self.assertNotIn("Banana Bread", self.db_titles())

    def test_complex_text_input(self):
        main = self.main()
        find_first(main, role_name="push button",
                   name="Add recipe").do_action_named("click")
        form = wait_until(
            lambda: find_first(self.app, role_name="frame",
                               name="Add recipe"),
            what="Add recipe form")
        texts = form_text_nodes(form)
        texts[0].text = "اختبار عربي 🥞"
        texts[1].text = "पालक पनीर का विवरण"
        texts[2].text = "番茄炒蛋的备注"
        form_button(form, "Save").do_action_named("click")
        wait_until(
            lambda: "اختبار عربي 🥞" in list_titles(self.main()) or None,
            what="complex-text title in list")
        recipe = self.db_recipe("اختبار عربي 🥞")
        self.assertIsNotNone(recipe)
        self.assertEqual(recipe["description"], "पालक पनीर का विवरण")
        self.assertEqual(recipe["notes"], "番茄炒蛋的备注")


if __name__ == "__main__":
    unittest.main(verbosity=2)
