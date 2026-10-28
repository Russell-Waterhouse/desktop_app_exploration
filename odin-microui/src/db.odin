package main

import "core:c"
import "core:fmt"
import "core:strings"

// SQLite access for the recipe manager.
//
// THE WRINKLE: Odin ships no SQLite package. vendor/ has no
// sqlite (unlike vendor:microui and vendor:raylib), and core/
// has no database package, so unlike the Rust version — which
// uses rusqlite with its bundled SQLite — this file declares
// the system SQLite C API by hand and links the system library:
//
//     foreign import sqlite3 "system:sqlite3"
//
// That means the build needs the system SQLite development
// package, not just the runtime library: libsqlite3-dev on
// Ubuntu (sqlite-devel on Fedora). The runtime library alone
// (libsqlite3-0) lets a built binary run, but not link, because
// linking needs the libsqlite3.so symlink and sqlite3.h header
// that only the -dev package provides. The resulting binary
// depends on libsqlite3.so at runtime (check with ldd), unlike
// the Rust version, whose SQLite is statically bundled.
//
// Schema matches the Rust version (rust-egui/src/db.rs):
// recipes (id, title, description, servings, image_path, notes), ingredients (id, recipe_id,
// position, amount, unit, name), steps (id, recipe_id, position,
// text), with foreign keys on. The database file, recipes.db,
// is created in the current working directory on first run
// and is git-ignored, not pushed.
//
// Unlike the Rust version, which opens a new connection per
// operation, this version holds one connection open for the
// app's lifetime (single-user app, no borrowing rules to work
// around in Odin) and closes it when main returns.

foreign import sqlite3 "system:sqlite3"

Sqlite_Db :: struct{}
Sqlite_Stmt :: struct{}

@(default_calling_convention="c")
foreign sqlite3 {
	sqlite3_open :: proc(filename: cstring, db: ^^Sqlite_Db) -> c.int ---
	sqlite3_close :: proc(db: ^Sqlite_Db) -> c.int ---
	sqlite3_exec :: proc(db: ^Sqlite_Db, sql: cstring, callback: rawptr, arg: rawptr, errmsg: ^^byte) -> c.int ---
	sqlite3_prepare_v2 :: proc(db: ^Sqlite_Db, sql: cstring, nbyte: c.int, stmt: ^^Sqlite_Stmt, tail: ^^byte) -> c.int ---
	sqlite3_step :: proc(stmt: ^Sqlite_Stmt) -> c.int ---
	sqlite3_finalize :: proc(stmt: ^Sqlite_Stmt) -> c.int ---
	sqlite3_column_text :: proc(stmt: ^Sqlite_Stmt, col: c.int) -> cstring ---
	sqlite3_column_int :: proc(stmt: ^Sqlite_Stmt, col: c.int) -> c.int ---
	sqlite3_column_int64 :: proc(stmt: ^Sqlite_Stmt, col: c.int) -> i64 ---
	sqlite3_column_type :: proc(stmt: ^Sqlite_Stmt, col: c.int) -> c.int ---
	sqlite3_bind_text :: proc(stmt: ^Sqlite_Stmt, idx: c.int, text: cstring, n: c.int, destructor: rawptr) -> c.int ---
	sqlite3_bind_int64 :: proc(stmt: ^Sqlite_Stmt, idx: c.int, val: i64) -> c.int ---
	sqlite3_bind_null :: proc(stmt: ^Sqlite_Stmt, idx: c.int) -> c.int ---
	sqlite3_errmsg :: proc(db: ^Sqlite_Db) -> cstring ---
	sqlite3_last_insert_rowid :: proc(db: ^Sqlite_Db) -> i64 ---
	sqlite3_free :: proc(p: rawptr) ---
}

SQLITE_OK :: 0
SQLITE_ROW :: 100
SQLITE_DONE :: 101
SQLITE_NULL :: 5

// Every db proc here returns "" on success, or an error
// message on failure. main shows a non-empty result in the
// detail pane instead of crashing, like the Rust version.

db_error :: proc(db: ^Sqlite_Db, what: string) -> string {
	msg, _ := strings.clone_from_cstring(sqlite3_errmsg(db))
	return fmt.tprintf("%s: %s", what, msg)
}

exec_sql :: proc(db: ^Sqlite_Db, sql: string) -> string {
	csql := strings.clone_to_cstring(sql)
	errmsg: ^byte
	if rc := sqlite3_exec(db, csql, nil, nil, &errmsg); rc != SQLITE_OK {
		msg, _ := strings.clone_from_cstring(cstring(errmsg))
		sqlite3_free(errmsg)
		return fmt.tprintf("sqlite exec failed (%s): %s", sql, msg)
	}
	return ""
}

prepare :: proc(db: ^Sqlite_Db, sql: string) -> (^Sqlite_Stmt, string) {
	csql := strings.clone_to_cstring(sql)
	stmt: ^Sqlite_Stmt
	if rc := sqlite3_prepare_v2(db, csql, -1, &stmt, nil); rc != SQLITE_OK {
		return nil, db_error(db, fmt.tprintf("prepare failed (%s)", sql))
	}
	return stmt, ""
}

// Bind a string with SQLITE_STATIC (nil destructor): the
// cstring must outlive the step, which holds here because
// these cstrings are heap-allocated and never freed during
// the insert, and each statement is stepped before the next
// bind.
bind_str :: proc(stmt: ^Sqlite_Stmt, idx: c.int, s: string) -> string {
	cs := strings.clone_to_cstring(s)
	if rc := sqlite3_bind_text(stmt, idx, cs, i32(len(s)), nil); rc != SQLITE_OK {
		return fmt.tprintf("bind_text failed (param %d)", idx)
	}
	return ""
}

column_string :: proc(stmt: ^Sqlite_Stmt, col: c.int) -> string {
	if sqlite3_column_type(stmt, col) == SQLITE_NULL {
		return ""
	}
	s, _ := strings.clone_from_cstring(sqlite3_column_text(stmt, col))
	return s
}

open_database :: proc(path: string) -> (^Sqlite_Db, string) {
	cpath := strings.clone_to_cstring(path)
	db: ^Sqlite_Db
	if rc := sqlite3_open(cpath, &db); rc != SQLITE_OK {
		msg := ""
		if db != nil {
			msg, _ = strings.clone_from_cstring(sqlite3_errmsg(db))
			sqlite3_close(db)
		}
		return nil, fmt.tprintf("could not open %s: %s", path, msg)
	}
	return db, ""
}

close_database :: proc(db: ^Sqlite_Db) {
	if db != nil {
		sqlite3_close(db)
	}
}

ensure_schema_and_seed :: proc(db: ^Sqlite_Db, seed: []Recipe) -> string {
	if err := exec_sql(db, `PRAGMA foreign_keys = ON;
		CREATE TABLE IF NOT EXISTS recipes (
			id INTEGER PRIMARY KEY,
			title TEXT NOT NULL,
			description TEXT NOT NULL,
			servings INTEGER NOT NULL,
			image_path TEXT,
			notes TEXT NOT NULL
		);
		CREATE TABLE IF NOT EXISTS ingredients (
			id INTEGER PRIMARY KEY,
			recipe_id INTEGER NOT NULL REFERENCES recipes(id),
			position INTEGER NOT NULL,
			amount TEXT NOT NULL,
			unit TEXT NOT NULL,
			name TEXT NOT NULL
		);
		CREATE TABLE IF NOT EXISTS steps (
			id INTEGER PRIMARY KEY,
			recipe_id INTEGER NOT NULL REFERENCES recipes(id),
			position INTEGER NOT NULL,
			text TEXT NOT NULL
		);`); err != "" {
		return err
	}

	// Seed once, only when the recipes table is empty.
	stmt, err := prepare(db, "SELECT COUNT(*) FROM recipes")
	if err != "" {
		return err
	}
	count: i64
	if rc := sqlite3_step(stmt); rc == SQLITE_ROW {
		count = sqlite3_column_int64(stmt, 0)
	} else {
		sqlite3_finalize(stmt)
		return db_error(db, "counting recipes")
	}
	sqlite3_finalize(stmt)
	if count != 0 {
		return ""
	}

	if err := exec_sql(db, "BEGIN"); err != "" {
		return err
	}
	// On any insert failure, roll back so a partial seed
	// is not left behind for the next run to build on.
	seed_failed := false
	seed_err := ""
	for recipe in seed {
		rstmt, rerr := prepare(db, `INSERT INTO recipes
			(title, description, servings, image_path, notes)
			VALUES (?1, ?2, ?3, ?4, ?5)`)
		if rerr != "" {
			seed_failed, seed_err = true, rerr
			break
		}
		if e := bind_str(rstmt, 1, recipe.title); e != "" {
			seed_failed, seed_err = true, e
		} else if e := bind_str(rstmt, 2, recipe.description); e != "" {
			seed_failed, seed_err = true, e
		} else if rc := sqlite3_bind_int64(rstmt, 3, i64(recipe.servings)); rc != SQLITE_OK {
			seed_failed, seed_err = true, "bind servings"
		} else if recipe.image_path == "" {
			if rc := sqlite3_bind_null(rstmt, 4); rc != SQLITE_OK {
				seed_failed, seed_err = true, "bind image_path"
			}
		} else if e := bind_str(rstmt, 4, recipe.image_path); e != "" {
			seed_failed, seed_err = true, e
		}
		if !seed_failed {
			if e := bind_str(rstmt, 5, recipe.notes); e != "" {
				seed_failed, seed_err = true, e
			}
		}
		if !seed_failed {
			if rc := sqlite3_step(rstmt); rc != SQLITE_DONE {
				seed_failed, seed_err = true, db_error(db, "inserting recipe")
			}
		}
		sqlite3_finalize(rstmt)
		if seed_failed {
			break
		}
		recipe_id := sqlite3_last_insert_rowid(db)

		for ingredient, i in recipe.ingredients {
			istmt, ierr := prepare(db, `INSERT INTO ingredients
				(recipe_id, position, amount, unit, name) VALUES (?1, ?2, ?3, ?4, ?5)`)
			if ierr != "" {
				seed_failed, seed_err = true, ierr
				break
			}
			failed := false
			if rc := sqlite3_bind_int64(istmt, 1, recipe_id); rc != SQLITE_OK {
				failed = true
			} else if rc := sqlite3_bind_int64(istmt, 2, i64(i)); rc != SQLITE_OK {
				failed = true
			} else if e := bind_str(istmt, 3, ingredient.amount); e != "" {
				failed, seed_err = true, e
			} else if e := bind_str(istmt, 4, ingredient.unit); e != "" {
				failed, seed_err = true, e
			} else if e := bind_str(istmt, 5, ingredient.name); e != "" {
				failed, seed_err = true, e
			} else if rc := sqlite3_step(istmt); rc != SQLITE_DONE {
				failed, seed_err = true, db_error(db, "inserting ingredient")
			}
			sqlite3_finalize(istmt)
			if failed {
				seed_failed = true
				break
			}
		}
		if seed_failed {
			break
		}

		for step, i in recipe.steps {
			sstmt, serr := prepare(db, `INSERT INTO steps
				(recipe_id, position, text) VALUES (?1, ?2, ?3)`)
			if serr != "" {
				seed_failed, seed_err = true, serr
				break
			}
			failed := false
			if rc := sqlite3_bind_int64(sstmt, 1, recipe_id); rc != SQLITE_OK {
				failed = true
			} else if rc := sqlite3_bind_int64(sstmt, 2, i64(i)); rc != SQLITE_OK {
				failed = true
			} else if e := bind_str(sstmt, 3, step); e != "" {
				failed, seed_err = true, e
			} else if rc := sqlite3_step(sstmt); rc != SQLITE_DONE {
				failed, seed_err = true, db_error(db, "inserting step")
			}
			sqlite3_finalize(sstmt)
			if failed {
				seed_failed = true
				break
			}
		}
		if seed_failed {
			break
		}
	}
	if seed_failed {
		exec_sql(db, "ROLLBACK")
		return seed_err
	}
	return exec_sql(db, "COMMIT")
}

load_recipes :: proc(db: ^Sqlite_Db) -> ([]Recipe, string) {
	stmt, err := prepare(db, `SELECT id, title, description, servings,
		image_path, notes FROM recipes ORDER BY id`)
	if err != "" {
		return nil, err
	}
	recipes := make([dynamic]Recipe)
	for sqlite3_step(stmt) == SQLITE_ROW {
		append(&recipes, Recipe{
			id           = sqlite3_column_int64(stmt, 0),
			title        = column_string(stmt, 1),
			description  = column_string(stmt, 2),
			servings     = int(sqlite3_column_int(stmt, 3)),
			image_path   = column_string(stmt, 4),
			notes        = column_string(stmt, 5),
		})
	}
	sqlite3_finalize(stmt)

	for &recipe in recipes {
		istmt, ierr := prepare(db, `SELECT amount, unit, name FROM ingredients
			WHERE recipe_id = ?1 ORDER BY position`)
		if ierr != "" {
			return nil, ierr
		}
		sqlite3_bind_int64(istmt, 1, recipe.id)
		ingredients := make([dynamic]Ingredient)
		for sqlite3_step(istmt) == SQLITE_ROW {
			append(&ingredients, Ingredient{
				amount = column_string(istmt, 0),
				unit   = column_string(istmt, 1),
				name   = column_string(istmt, 2),
			})
		}
		sqlite3_finalize(istmt)
		recipe.ingredients = ingredients[:]

		sstmt, serr := prepare(db, `SELECT text FROM steps
			WHERE recipe_id = ?1 ORDER BY position`)
		if serr != "" {
			return nil, serr
		}
		sqlite3_bind_int64(sstmt, 1, recipe.id)
		steps := make([dynamic]string)
		for sqlite3_step(sstmt) == SQLITE_ROW {
			append(&steps, column_string(sstmt, 0))
		}
		sqlite3_finalize(sstmt)
		recipe.steps = steps[:]
	}
	return recipes[:], ""
}

// Insert a recipe's ingredients and steps, in position order.
// Used by insert_recipe and update_recipe; the seed path in
// ensure_schema_and_seed has its own inline copy, left alone.
insert_children :: proc(db: ^Sqlite_Db, recipe_id: i64, recipe: Recipe) -> string {
	for ingredient, i in recipe.ingredients {
		stmt, err := prepare(db, `INSERT INTO ingredients
			(recipe_id, position, amount, unit, name) VALUES (?1, ?2, ?3, ?4, ?5)`)
		if err != "" {
			return err
		}
		failed := ""
		if rc := sqlite3_bind_int64(stmt, 1, recipe_id); rc != SQLITE_OK {
			failed = "bind ingredient recipe_id"
		} else if rc := sqlite3_bind_int64(stmt, 2, i64(i)); rc != SQLITE_OK {
			failed = "bind ingredient position"
		} else if e := bind_str(stmt, 3, ingredient.amount); e != "" {
			failed = e
		} else if e := bind_str(stmt, 4, ingredient.unit); e != "" {
			failed = e
		} else if e := bind_str(stmt, 5, ingredient.name); e != "" {
			failed = e
		} else if rc := sqlite3_step(stmt); rc != SQLITE_DONE {
			failed = db_error(db, "inserting ingredient")
		}
		sqlite3_finalize(stmt)
		if failed != "" {
			return failed
		}
	}
	for step, i in recipe.steps {
		stmt, err := prepare(db, `INSERT INTO steps
			(recipe_id, position, text) VALUES (?1, ?2, ?3)`)
		if err != "" {
			return err
		}
		failed := ""
		if rc := sqlite3_bind_int64(stmt, 1, recipe_id); rc != SQLITE_OK {
			failed = "bind step recipe_id"
		} else if rc := sqlite3_bind_int64(stmt, 2, i64(i)); rc != SQLITE_OK {
			failed = "bind step position"
		} else if e := bind_str(stmt, 3, step); e != "" {
			failed = e
		} else if rc := sqlite3_step(stmt); rc != SQLITE_DONE {
			failed = db_error(db, "inserting step")
		}
		sqlite3_finalize(stmt)
		if failed != "" {
			return failed
		}
	}
	return ""
}

// Insert a new recipe (and its ingredients and steps) in one
// transaction. Returns the new row id, like the Rust version's
// insert_recipe. An empty image_path is stored as NULL.
insert_recipe :: proc(db: ^Sqlite_Db, recipe: Recipe) -> (i64, string) {
	if err := exec_sql(db, "BEGIN"); err != "" {
		return 0, err
	}
	stmt, err := prepare(db, `INSERT INTO recipes
		(title, description, servings, image_path, notes)
		VALUES (?1, ?2, ?3, ?4, ?5)`)
	if err != "" {
		exec_sql(db, "ROLLBACK")
		return 0, err
	}
	failed := ""
	if e := bind_str(stmt, 1, recipe.title); e != "" {
		failed = e
	} else if e := bind_str(stmt, 2, recipe.description); e != "" {
		failed = e
	} else if rc := sqlite3_bind_int64(stmt, 3, i64(recipe.servings)); rc != SQLITE_OK {
		failed = "bind servings"
	} else if recipe.image_path == "" {
		if rc := sqlite3_bind_null(stmt, 4); rc != SQLITE_OK {
			failed = "bind image_path"
		}
	} else if e := bind_str(stmt, 4, recipe.image_path); e != "" {
		failed = e
	}
	if failed == "" {
		if e := bind_str(stmt, 5, recipe.notes); e != "" {
			failed = e
		}
	}
	if failed == "" {
		if rc := sqlite3_step(stmt); rc != SQLITE_DONE {
			failed = db_error(db, "inserting recipe")
		}
	}
	sqlite3_finalize(stmt)
	if failed != "" {
		exec_sql(db, "ROLLBACK")
		return 0, failed
	}
	recipe_id := sqlite3_last_insert_rowid(db)
	if err := insert_children(db, recipe_id, recipe); err != "" {
		exec_sql(db, "ROLLBACK")
		return 0, err
	}
	if err := exec_sql(db, "COMMIT"); err != "" {
		return 0, err
	}
	return recipe_id, ""
}

// Update a recipe and replace its ingredients and steps, in
// one transaction, like the Rust version's update_recipe.
update_recipe :: proc(db: ^Sqlite_Db, recipe: Recipe) -> string {
	if err := exec_sql(db, "BEGIN"); err != "" {
		return err
	}
	stmt, err := prepare(db, `UPDATE recipes SET title = ?1,
		description = ?2, servings = ?3, image_path = ?4, notes = ?5
		WHERE id = ?6`)
	if err != "" {
		exec_sql(db, "ROLLBACK")
		return err
	}
	failed := ""
	if e := bind_str(stmt, 1, recipe.title); e != "" {
		failed = e
	} else if e := bind_str(stmt, 2, recipe.description); e != "" {
		failed = e
	} else if rc := sqlite3_bind_int64(stmt, 3, i64(recipe.servings)); rc != SQLITE_OK {
		failed = "bind servings"
	} else if recipe.image_path == "" {
		if rc := sqlite3_bind_null(stmt, 4); rc != SQLITE_OK {
			failed = "bind image_path"
		}
	} else if e := bind_str(stmt, 4, recipe.image_path); e != "" {
		failed = e
	}
	if failed == "" {
		if e := bind_str(stmt, 5, recipe.notes); e != "" {
			failed = e
		} else if rc := sqlite3_bind_int64(stmt, 6, recipe.id); rc != SQLITE_OK {
			failed = "bind id"
		} else if rc := sqlite3_step(stmt); rc != SQLITE_DONE {
			failed = db_error(db, "updating recipe")
		}
	}
	sqlite3_finalize(stmt)
	if failed != "" {
		exec_sql(db, "ROLLBACK")
		return failed
	}
	// The id comes from our own loaded data, so formatting it
	// into these statements is safe; it avoids three more binds.
	if err := exec_sql(db, fmt.tprintf("DELETE FROM ingredients WHERE recipe_id = %d", recipe.id)); err != "" {
		exec_sql(db, "ROLLBACK")
		return err
	}
	if err := exec_sql(db, fmt.tprintf("DELETE FROM steps WHERE recipe_id = %d", recipe.id)); err != "" {
		exec_sql(db, "ROLLBACK")
		return err
	}
	if err := insert_children(db, recipe.id, recipe); err != "" {
		exec_sql(db, "ROLLBACK")
		return err
	}
	return exec_sql(db, "COMMIT")
}

// Delete a recipe and its ingredients and steps, in one
// transaction. The schema has no ON DELETE CASCADE, so the
// children are deleted explicitly, before the recipe row.
delete_recipe :: proc(db: ^Sqlite_Db, id: i64) -> string {
	if err := exec_sql(db, "BEGIN"); err != "" {
		return err
	}
	if err := exec_sql(db, fmt.tprintf("DELETE FROM ingredients WHERE recipe_id = %d", id)); err != "" {
		exec_sql(db, "ROLLBACK")
		return err
	}
	if err := exec_sql(db, fmt.tprintf("DELETE FROM steps WHERE recipe_id = %d", id)); err != "" {
		exec_sql(db, "ROLLBACK")
		return err
	}
	if err := exec_sql(db, fmt.tprintf("DELETE FROM recipes WHERE id = %d", id)); err != "" {
		exec_sql(db, "ROLLBACK")
		return err
	}
	return exec_sql(db, "COMMIT")
}
