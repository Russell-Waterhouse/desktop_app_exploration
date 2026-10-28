const std = @import("std");

// SQLite storage for the recipe manager, matching the Rust
// (rust-egui/src/db.rs) and Odin (odin-microui/src/db.odin)
// versions.
//
// THE WRINKLE, same as Odin's and one step further: Zig ships
// no SQLite package, and Zig 0.17 removed @cImport, so this
// file declares the system SQLite C API by hand (opaque
// sqlite3/sqlite3_stmt types plus extern fn declarations) and
// links the system library (build.zig: root_module
// .linkSystemLibrary("sqlite3")). That means the build needs
// the system SQLite development package, not just the runtime
// library: libsqlite3-dev on Ubuntu (sqlite-devel on Fedora).
// The runtime library alone lets a built binary run, but not
// link, because linking needs the libsqlite3.so symlink and
// the sqlite3.h header that only the -dev package provides.
// The resulting binary depends on libsqlite3.so at runtime
// (check with ldd), unlike the Rust version, whose SQLite is
// statically bundled.
//
// Schema matches the Rust and Odin versions: recipes (id,
// title, description, servings, image_path, notes),
// ingredients (id, recipe_id, position, amount, unit, name),
// steps (id, recipe_id, position, text), with foreign keys on.
// The database file, recipes.db, is created in the current
// working directory on first run and is git-ignored, not
// pushed.
//
// Unlike the Rust version, which opens a new connection per
// operation, this version holds one connection open for the
// app's lifetime (single-user app) and never closes it, like
// the Odin version. All loaded data is allocated from one
// arena that lives for the app's lifetime and is never freed.
//
// Loading is lazy and happens once, on the first frame: the
// UI calls ensureLoaded() at the top of every frame, and it
// is a no-op after the first call. On failure it records the
// error in load_error instead of crashing; main shows that
// error in the detail pane.

const sqlite3 = opaque {};
const sqlite3_stmt = opaque {};

extern fn sqlite3_open([*c]const u8, *?*sqlite3) c_int;
extern fn sqlite3_close(*sqlite3) c_int;
extern fn sqlite3_exec(*sqlite3, [*c]const u8, ?*anyopaque, ?*anyopaque, [*c][*c]u8) c_int;
extern fn sqlite3_prepare_v2(*sqlite3, [*c]const u8, c_int, *?*sqlite3_stmt, [*c][*c]const u8) c_int;
extern fn sqlite3_step(*sqlite3_stmt) c_int;
extern fn sqlite3_finalize(*sqlite3_stmt) c_int;
extern fn sqlite3_column_text(*sqlite3_stmt, c_int) [*c]const u8;
extern fn sqlite3_column_int(*sqlite3_stmt, c_int) c_int;
extern fn sqlite3_column_int64(*sqlite3_stmt, c_int) i64;
extern fn sqlite3_column_type(*sqlite3_stmt, c_int) c_int;
extern fn sqlite3_bind_text(*sqlite3_stmt, c_int, [*c]const u8, c_int, ?*anyopaque) c_int;
extern fn sqlite3_bind_int64(*sqlite3_stmt, c_int, i64) c_int;
extern fn sqlite3_bind_null(*sqlite3_stmt, c_int) c_int;
extern fn sqlite3_errmsg(*sqlite3) [*c]const u8;
extern fn sqlite3_last_insert_rowid(*sqlite3) i64;
extern fn sqlite3_free(?*anyopaque) void;

const SQLITE_OK = 0;
const SQLITE_ROW = 100;
const SQLITE_DONE = 101;
const SQLITE_NULL = 5;

pub const Ingredient = struct {
    amount: []const u8,
    unit: []const u8,
    name: []const u8,
};

pub const Recipe = struct {
    id: i64 = 0,
    title: []const u8,
    description: []const u8,
    servings: u32,
    image_path: []const u8 = "",
    ingredients: []const Ingredient,
    steps: []const []const u8,
    notes: []const u8,
};

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const alloc = arena.allocator();

/// Recipes loaded from the database (empty until a successful
/// load, and empty forever if loading failed).
pub var recipes: []Recipe = &.{};

/// Non-null when loading failed; main shows it in the detail
/// pane instead of crashing.
pub var load_error: ?[]const u8 = null;

var loaded: bool = false;
var db_handle: ?*sqlite3 = null;

fn setError(db: ?*sqlite3, comptime fmt: []const u8, args: anytype) anyerror {
    const detail: []const u8 = if (db) |d|
        std.mem.span(@as([*:0]const u8, @ptrCast(sqlite3_errmsg(d))))
    else
        "no database handle";
    load_error = std.fmt.allocPrint(alloc, fmt ++ ": {s}", args ++ .{detail}) catch fmt;
    return error.Sqlite;
}

fn exec(db: *sqlite3, sql: [*:0]const u8) !void {
    var errmsg: [*c]u8 = null;
    const rc = sqlite3_exec(db, sql, null, null, &errmsg);
    if (rc != SQLITE_OK) {
        const detail: []const u8 = if (errmsg) |e|
            std.mem.span(@as([*:0]const u8, @ptrCast(e)))
        else
            "unknown error";
        load_error = std.fmt.allocPrint(alloc, "sqlite exec failed: {s}", .{detail}) catch "sqlite exec failed";
        if (errmsg) |e| sqlite3_free(e);
        return error.Sqlite;
    }
}

fn prepare(db: *sqlite3, sql: [*:0]const u8) !*sqlite3_stmt {
    var stmt: ?*sqlite3_stmt = null;
    const rc = sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != SQLITE_OK or stmt == null) return setError(db, "prepare failed ({s})", .{sql});
    return stmt.?;
}

fn bindText(stmt: *sqlite3_stmt, idx: c_int, text: []const u8) !void {
    // SQLITE_STATIC (null destructor): the text must outlive
    // the step, which holds here because seed texts are string
    // literals and each statement is stepped before the next
    // bind.
    const rc = sqlite3_bind_text(stmt, idx, text.ptr, @intCast(text.len), null);
    if (rc != SQLITE_OK) return error.Sqlite;
}

fn bindInt(stmt: *sqlite3_stmt, idx: c_int, value: i64) !void {
    const rc = sqlite3_bind_int64(stmt, idx, value);
    if (rc != SQLITE_OK) return error.Sqlite;
}

fn columnText(stmt: *sqlite3_stmt, col: c_int) []const u8 {
    if (sqlite3_column_type(stmt, col) == SQLITE_NULL) return "";
    const ptr = sqlite3_column_text(stmt, col);
    if (ptr == null) return "";
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
    return alloc.dupe(u8, text) catch "";
}

fn openDatabase(path: [*:0]const u8) !*sqlite3 {
    var db: ?*sqlite3 = null;
    const rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK or db == null) {
        if (db) |d| {
            const err = setError(d, "could not open {s}", .{path});
            _ = sqlite3_close(d);
            return err;
        }
        return error.Sqlite;
    }
    return db.?;
}

fn ensureSchemaAndSeed(db: *sqlite3, seed: []const Recipe) !void {
    try exec(db,
        \\PRAGMA foreign_keys = ON;
        \\CREATE TABLE IF NOT EXISTS recipes (
        \\    id INTEGER PRIMARY KEY,
        \\    title TEXT NOT NULL,
        \\    description TEXT NOT NULL,
        \\    servings INTEGER NOT NULL,
        \\    image_path TEXT,
        \\    notes TEXT NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS ingredients (
        \\    id INTEGER PRIMARY KEY,
        \\    recipe_id INTEGER NOT NULL REFERENCES recipes(id),
        \\    position INTEGER NOT NULL,
        \\    amount TEXT NOT NULL,
        \\    unit TEXT NOT NULL,
        \\    name TEXT NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS steps (
        \\    id INTEGER PRIMARY KEY,
        \\    recipe_id INTEGER NOT NULL REFERENCES recipes(id),
        \\    position INTEGER NOT NULL,
        \\    text TEXT NOT NULL
        \\);
    );

    // Seed once, only when the recipes table is empty.
    const count_stmt = try prepare(db, "SELECT COUNT(*) FROM recipes");
    defer _ = sqlite3_finalize(count_stmt);
    var count: i64 = 0;
    if (sqlite3_step(count_stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(count_stmt, 0);
    } else {
        return setError(db, "counting recipes", .{});
    }
    if (count != 0) return;

    try exec(db, "BEGIN");
    errdefer exec(db, "ROLLBACK") catch {};
    for (seed) |recipe| {
        const rstmt = try prepare(db,
            \\INSERT INTO recipes
            \\  (title, description, servings, image_path, notes)
            \\  VALUES (?1, ?2, ?3, ?4, ?5)
        );
        defer _ = sqlite3_finalize(rstmt);
        try bindText(rstmt, 1, recipe.title);
        try bindText(rstmt, 2, recipe.description);
        try bindInt(rstmt, 3, recipe.servings);
        if (recipe.image_path.len == 0) {
            if (sqlite3_bind_null(rstmt, 4) != SQLITE_OK) return error.Sqlite;
        } else {
            try bindText(rstmt, 4, recipe.image_path);
        }
        try bindText(rstmt, 5, recipe.notes);
        if (sqlite3_step(rstmt) != SQLITE_DONE) {
            return setError(db, "inserting recipe", .{});
        }
        const recipe_id = sqlite3_last_insert_rowid(db);

        for (recipe.ingredients, 0..) |ingredient, i| {
            const istmt = try prepare(db,
                \\INSERT INTO ingredients
                \\  (recipe_id, position, amount, unit, name)
                \\  VALUES (?1, ?2, ?3, ?4, ?5)
            );
            defer _ = sqlite3_finalize(istmt);
            try bindInt(istmt, 1, recipe_id);
            try bindInt(istmt, 2, @intCast(i));
            try bindText(istmt, 3, ingredient.amount);
            try bindText(istmt, 4, ingredient.unit);
            try bindText(istmt, 5, ingredient.name);
            if (sqlite3_step(istmt) != SQLITE_DONE) {
                return setError(db, "inserting ingredient", .{});
            }
        }

        for (recipe.steps, 0..) |step, i| {
            const sstmt = try prepare(db,
                \\INSERT INTO steps
                \\  (recipe_id, position, text)
                \\  VALUES (?1, ?2, ?3)
            );
            defer _ = sqlite3_finalize(sstmt);
            try bindInt(sstmt, 1, recipe_id);
            try bindInt(sstmt, 2, @intCast(i));
            try bindText(sstmt, 3, step);
            if (sqlite3_step(sstmt) != SQLITE_DONE) {
                return setError(db, "inserting step", .{});
            }
        }
    }
    try exec(db, "COMMIT");
}

fn loadRecipes(db: *sqlite3) ![]Recipe {
    const stmt = try prepare(db,
        \\SELECT id, title, description, servings, image_path, notes
        \\  FROM recipes ORDER BY id
    );
    defer _ = sqlite3_finalize(stmt);
    var list: std.ArrayList(Recipe) = .empty;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        var recipe = Recipe{
            .id = sqlite3_column_int64(stmt, 0),
            .title = columnText(stmt, 1),
            .description = columnText(stmt, 2),
            .servings = @intCast(sqlite3_column_int(stmt, 3)),
            .image_path = columnText(stmt, 4),
            .ingredients = &.{},
            .steps = &.{},
            .notes = columnText(stmt, 5),
        };

        const istmt = try prepare(db,
            \\SELECT amount, unit, name FROM ingredients
            \\  WHERE recipe_id = ?1 ORDER BY position
        );
        defer _ = sqlite3_finalize(istmt);
        try bindInt(istmt, 1, recipe.id);
        var ingredients: std.ArrayList(Ingredient) = .empty;
        while (sqlite3_step(istmt) == SQLITE_ROW) {
            try ingredients.append(alloc, .{
                .amount = columnText(istmt, 0),
                .unit = columnText(istmt, 1),
                .name = columnText(istmt, 2),
            });
        }
        recipe.ingredients = try ingredients.toOwnedSlice(alloc);

        const sstmt = try prepare(db,
            \\SELECT text FROM steps
            \\  WHERE recipe_id = ?1 ORDER BY position
        );
        defer _ = sqlite3_finalize(sstmt);
        try bindInt(sstmt, 1, recipe.id);
        var steps: std.ArrayList([]const u8) = .empty;
        while (sqlite3_step(sstmt) == SQLITE_ROW) {
            try steps.append(alloc, columnText(sstmt, 0));
        }
        recipe.steps = try steps.toOwnedSlice(alloc);

        try list.append(alloc, recipe);
    }
    return list.toOwnedSlice(alloc);
}

fn insertChildren(db: *sqlite3, recipe_id: i64, recipe: Recipe) !void {
    for (recipe.ingredients, 0..) |ingredient, i| {
        const istmt = try prepare(db,
            \\INSERT INTO ingredients
            \\  (recipe_id, position, amount, unit, name)
            \\  VALUES (?1, ?2, ?3, ?4, ?5)
        );
        defer _ = sqlite3_finalize(istmt);
        try bindInt(istmt, 1, recipe_id);
        try bindInt(istmt, 2, @intCast(i));
        try bindText(istmt, 3, ingredient.amount);
        try bindText(istmt, 4, ingredient.unit);
        try bindText(istmt, 5, ingredient.name);
        if (sqlite3_step(istmt) != SQLITE_DONE) {
            return setError(db, "inserting ingredient", .{});
        }
    }

    for (recipe.steps, 0..) |step, i| {
        const sstmt = try prepare(db,
            \\INSERT INTO steps
            \\  (recipe_id, position, text)
            \\  VALUES (?1, ?2, ?3)
        );
        defer _ = sqlite3_finalize(sstmt);
        try bindInt(sstmt, 1, recipe_id);
        try bindInt(sstmt, 2, @intCast(i));
        try bindText(sstmt, 3, step);
        if (sqlite3_step(sstmt) != SQLITE_DONE) {
            return setError(db, "inserting step", .{});
        }
    }
}

fn bindImagePath(stmt: *sqlite3_stmt, idx: c_int, image_path: []const u8) !void {
    if (image_path.len == 0) {
        if (sqlite3_bind_null(stmt, idx) != SQLITE_OK) return error.Sqlite;
    } else {
        try bindText(stmt, idx, image_path);
    }
}

/// Insert a recipe (id is ignored) and its children, in one
/// transaction. Returns the new recipe id. Like the Rust
/// version's insert_recipe; the caller reloads afterwards.
pub fn insertRecipe(recipe: Recipe) !i64 {
    const db = db_handle orelse return error.NoDatabase;
    try exec(db, "BEGIN");
    errdefer exec(db, "ROLLBACK") catch {};
    const rstmt = try prepare(db,
        \\INSERT INTO recipes
        \\  (title, description, servings, image_path, notes)
        \\  VALUES (?1, ?2, ?3, ?4, ?5)
    );
    defer _ = sqlite3_finalize(rstmt);
    try bindText(rstmt, 1, recipe.title);
    try bindText(rstmt, 2, recipe.description);
    try bindInt(rstmt, 3, recipe.servings);
    try bindImagePath(rstmt, 4, recipe.image_path);
    try bindText(rstmt, 5, recipe.notes);
    if (sqlite3_step(rstmt) != SQLITE_DONE) {
        return setError(db, "inserting recipe", .{});
    }
    const recipe_id = sqlite3_last_insert_rowid(db);
    try insertChildren(db, recipe_id, recipe);
    try exec(db, "COMMIT");
    return recipe_id;
}

/// Replace a recipe (by id) and its children, in one
/// transaction. Like the Rust version's update_recipe; the
/// caller reloads afterwards.
pub fn updateRecipe(recipe: Recipe) !void {
    const db = db_handle orelse return error.NoDatabase;
    try exec(db, "BEGIN");
    errdefer exec(db, "ROLLBACK") catch {};
    const rstmt = try prepare(db,
        \\UPDATE recipes SET title = ?1, description = ?2,
        \\  servings = ?3, image_path = ?4, notes = ?5
        \\  WHERE id = ?6
    );
    defer _ = sqlite3_finalize(rstmt);
    try bindText(rstmt, 1, recipe.title);
    try bindText(rstmt, 2, recipe.description);
    try bindInt(rstmt, 3, recipe.servings);
    try bindImagePath(rstmt, 4, recipe.image_path);
    try bindText(rstmt, 5, recipe.notes);
    try bindInt(rstmt, 6, recipe.id);
    if (sqlite3_step(rstmt) != SQLITE_DONE) {
        return setError(db, "updating recipe", .{});
    }
    // Children are deleted explicitly (no ON DELETE CASCADE
    // in the schema) and re-inserted from the draft below.
    {
        const dstmt = try prepare(db, "DELETE FROM ingredients WHERE recipe_id = ?1");
        defer _ = sqlite3_finalize(dstmt);
        try bindInt(dstmt, 1, recipe.id);
        if (sqlite3_step(dstmt) != SQLITE_DONE) {
            return setError(db, "deleting old ingredients", .{});
        }
    }
    {
        const dstmt = try prepare(db, "DELETE FROM steps WHERE recipe_id = ?1");
        defer _ = sqlite3_finalize(dstmt);
        try bindInt(dstmt, 1, recipe.id);
        if (sqlite3_step(dstmt) != SQLITE_DONE) {
            return setError(db, "deleting old steps", .{});
        }
    }
    try insertChildren(db, recipe.id, recipe);
    try exec(db, "COMMIT");
}

/// Delete a recipe and its children, in one transaction.
/// Like the Rust version's delete_recipe; the caller reloads
/// afterwards. (The schema has no ON DELETE CASCADE, so the
/// children are deleted explicitly first.)
pub fn deleteRecipe(id: i64) !void {
    const db = db_handle orelse return error.NoDatabase;
    try exec(db, "BEGIN");
    errdefer exec(db, "ROLLBACK") catch {};
    {
        const dstmt = try prepare(db, "DELETE FROM ingredients WHERE recipe_id = ?1");
        defer _ = sqlite3_finalize(dstmt);
        try bindInt(dstmt, 1, id);
        if (sqlite3_step(dstmt) != SQLITE_DONE) {
            return setError(db, "deleting ingredients", .{});
        }
    }
    {
        const dstmt = try prepare(db, "DELETE FROM steps WHERE recipe_id = ?1");
        defer _ = sqlite3_finalize(dstmt);
        try bindInt(dstmt, 1, id);
        if (sqlite3_step(dstmt) != SQLITE_DONE) {
            return setError(db, "deleting steps", .{});
        }
    }
    {
        const dstmt = try prepare(db, "DELETE FROM recipes WHERE id = ?1");
        defer _ = sqlite3_finalize(dstmt);
        try bindInt(dstmt, 1, id);
        if (sqlite3_step(dstmt) != SQLITE_DONE) {
            return setError(db, "deleting recipe", .{});
        }
    }
    try exec(db, "COMMIT");
}

/// Re-read recipes from the database after an insert, update,
/// or delete. Old slices leak into the app-lifetime arena,
/// which is fine for a test app of this size.
pub fn reload() !void {
    const db = db_handle orelse return error.NoDatabase;
    recipes = try loadRecipes(db);
}

/// Load from recipes.db in the current working directory on
/// the first call; later calls are no-ops. On failure,
/// load_error is set and recipes stays empty.
pub fn ensureLoaded(seed: []const Recipe) void {
    if (loaded) return;
    loaded = true;
    const db = openDatabase("recipes.db") catch return;
    db_handle = db;
    ensureSchemaAndSeed(db, seed) catch return;
    recipes = loadRecipes(db) catch return;
}
