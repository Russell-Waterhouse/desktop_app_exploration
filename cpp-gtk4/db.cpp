#include "db.h"

#include "seed.h"

#include <sqlite3.h>

// Defined below; declared here because insert_seed uses it.
bool insert_recipe_row(sqlite3* db, Recipe& recipe, std::string& error);

namespace {

bool exec_sql(sqlite3* db, const char* sql, std::string& error) {
    char* message = nullptr;
    if (sqlite3_exec(db, sql, nullptr, nullptr, &message) != SQLITE_OK) {
        error = message != nullptr ? message : sqlite3_errmsg(db);
        sqlite3_free(message);
        return false;
    }
    return true;
}

std::string column_text(sqlite3_stmt* stmt, int column) {
    // NULL (used for a missing image path) reads back as empty.
    if (sqlite3_column_type(stmt, column) == SQLITE_NULL) {
        return "";
    }
    const unsigned char* text = sqlite3_column_text(stmt, column);
    return text != nullptr ? reinterpret_cast<const char*>(text) : "";
}

bool bind_text(sqlite3_stmt* stmt, int index, const std::string& value) {
    return sqlite3_bind_text(stmt, index, value.c_str(), -1, SQLITE_TRANSIENT) ==
           SQLITE_OK;
}

bool step_done(sqlite3_stmt* stmt, std::string& error, sqlite3* db) {
    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        error = sqlite3_errmsg(db);
        return false;
    }
    return true;
}

bool prepare(sqlite3* db, const char* sql, sqlite3_stmt** stmt, std::string& error) {
    if (sqlite3_prepare_v2(db, sql, -1, stmt, nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
        return false;
    }
    return true;
}

// Writes one recipe's ingredients and steps (its id must already
// be set). The caller owns the transaction.
bool insert_children(sqlite3* db, const Recipe& recipe, std::string& error) {
    sqlite3_stmt* ingredient_stmt = nullptr;
    sqlite3_stmt* step_stmt = nullptr;
    bool ok = prepare(db,
                      "INSERT INTO ingredients (recipe_id, position, amount, "
                      "unit, name) VALUES (?, ?, ?, ?, ?);",
                      &ingredient_stmt, error) &&
              prepare(db,
                      "INSERT INTO steps (recipe_id, position, text) "
                      "VALUES (?, ?, ?);",
                      &step_stmt, error);

    if (ok) {
        for (int i = 0; i < static_cast<int>(recipe.ingredients.size()) && ok; ++i) {
            const Ingredient& ingredient = recipe.ingredients[i];
            sqlite3_reset(ingredient_stmt);
            sqlite3_clear_bindings(ingredient_stmt);
            if (sqlite3_bind_int64(ingredient_stmt, 1, recipe.id) != SQLITE_OK ||
                sqlite3_bind_int(ingredient_stmt, 2, i) != SQLITE_OK ||
                !bind_text(ingredient_stmt, 3, ingredient.amount) ||
                !bind_text(ingredient_stmt, 4, ingredient.unit) ||
                !bind_text(ingredient_stmt, 5, ingredient.name) ||
                !step_done(ingredient_stmt, error, db)) {
                ok = false;
            }
        }
    }
    if (ok) {
        for (int i = 0; i < static_cast<int>(recipe.steps.size()) && ok; ++i) {
            sqlite3_reset(step_stmt);
            sqlite3_clear_bindings(step_stmt);
            if (sqlite3_bind_int64(step_stmt, 1, recipe.id) != SQLITE_OK ||
                sqlite3_bind_int(step_stmt, 2, i) != SQLITE_OK ||
                !bind_text(step_stmt, 3, recipe.steps[i]) ||
                !step_done(step_stmt, error, db)) {
                ok = false;
            }
        }
    }

    sqlite3_finalize(ingredient_stmt);
    sqlite3_finalize(step_stmt);
    return ok;
}

bool insert_seed(sqlite3* db, std::string& error) {
    if (!exec_sql(db, "BEGIN;", error)) {
        return false;
    }
    bool ok = true;
    for (Recipe recipe : seed_recipes()) {
        if (!insert_recipe_row(db, recipe, error) ||
            !insert_children(db, recipe, error)) {
            ok = false;
            break;
        }
    }
    std::string tail_error;
    if (!exec_sql(db, ok ? "COMMIT;" : "ROLLBACK;", tail_error)) {
        if (ok) {
            error = tail_error;
            return false;
        }
    }
    return ok;
}

}  // namespace

bool open_database(const std::string& path, sqlite3** db, std::string& error) {
    if (sqlite3_open(path.c_str(), db) != SQLITE_OK) {
        error = *db != nullptr ? sqlite3_errmsg(*db) : "Could not open database";
        if (*db != nullptr) {
            sqlite3_close(*db);
            *db = nullptr;
        }
        return false;
    }
    // Foreign keys are off by default in SQLite; enable them for
    // this connection so recipe deletes cascade to children.
    if (!exec_sql(*db, "PRAGMA foreign_keys = ON;", error)) {
        sqlite3_close(*db);
        *db = nullptr;
        return false;
    }
    return true;
}

bool init_and_seed(sqlite3* db, std::string& error) {
    if (!exec_sql(db,
                  "CREATE TABLE IF NOT EXISTS recipes ("
                  "id INTEGER PRIMARY KEY, "
                  "title TEXT NOT NULL, "
                  "description TEXT NOT NULL DEFAULT '', "
                  "servings INTEGER NOT NULL, "
                  "image_path TEXT, "
                  "notes TEXT NOT NULL DEFAULT '');",
                  error) ||
        !exec_sql(db,
                  "CREATE TABLE IF NOT EXISTS ingredients ("
                  "id INTEGER PRIMARY KEY, "
                  "recipe_id INTEGER NOT NULL REFERENCES recipes(id) "
                  "ON DELETE CASCADE, "
                  "position INTEGER NOT NULL, "
                  "amount TEXT NOT NULL, "
                  "unit TEXT NOT NULL, "
                  "name TEXT NOT NULL);",
                  error) ||
        !exec_sql(db,
                  "CREATE TABLE IF NOT EXISTS steps ("
                  "id INTEGER PRIMARY KEY, "
                  "recipe_id INTEGER NOT NULL REFERENCES recipes(id) "
                  "ON DELETE CASCADE, "
                  "position INTEGER NOT NULL, "
                  "text TEXT NOT NULL);",
                  error)) {
        return false;
    }

    sqlite3_stmt* stmt = nullptr;
    if (!prepare(db, "SELECT COUNT(*) FROM recipes;", &stmt, error)) {
        return false;
    }
    int count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int(stmt, 0);
    } else {
        error = sqlite3_errmsg(db);
        sqlite3_finalize(stmt);
        return false;
    }
    sqlite3_finalize(stmt);

    if (count > 0) {
        return true;
    }
    return insert_seed(db, error);
}

bool load_recipes(sqlite3* db, std::vector<Recipe>& recipes, std::string& error) {
    recipes.clear();

    sqlite3_stmt* stmt = nullptr;
    if (!prepare(db,
                 "SELECT id, title, description, servings, "
                 "image_path, notes FROM recipes ORDER BY id;",
                 &stmt, error)) {
        return false;
    }
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        Recipe recipe;
        recipe.id = sqlite3_column_int64(stmt, 0);
        recipe.title = column_text(stmt, 1);
        recipe.description = column_text(stmt, 2);
        recipe.servings = sqlite3_column_int(stmt, 3);
        recipe.image_path = column_text(stmt, 4);
        recipe.notes = column_text(stmt, 5);
        recipes.push_back(recipe);
    }
    sqlite3_finalize(stmt);

    sqlite3_stmt* ingredient_stmt = nullptr;
    sqlite3_stmt* step_stmt = nullptr;
    if (!prepare(db,
                 "SELECT amount, unit, name FROM ingredients "
                 "WHERE recipe_id = ? ORDER BY position;",
                 &ingredient_stmt, error) ||
        !prepare(db,
                 "SELECT text FROM steps WHERE recipe_id = ? "
                 "ORDER BY position;",
                 &step_stmt, error)) {
        sqlite3_finalize(ingredient_stmt);
        sqlite3_finalize(step_stmt);
        return false;
    }

    for (Recipe& recipe : recipes) {
        sqlite3_reset(ingredient_stmt);
        sqlite3_clear_bindings(ingredient_stmt);
        sqlite3_bind_int64(ingredient_stmt, 1, recipe.id);
        while (sqlite3_step(ingredient_stmt) == SQLITE_ROW) {
            Ingredient ingredient;
            ingredient.amount = column_text(ingredient_stmt, 0);
            ingredient.unit = column_text(ingredient_stmt, 1);
            ingredient.name = column_text(ingredient_stmt, 2);
            recipe.ingredients.push_back(ingredient);
        }

        sqlite3_reset(step_stmt);
        sqlite3_clear_bindings(step_stmt);
        sqlite3_bind_int64(step_stmt, 1, recipe.id);
        while (sqlite3_step(step_stmt) == SQLITE_ROW) {
            recipe.steps.push_back(column_text(step_stmt, 0));
        }
    }

    sqlite3_finalize(ingredient_stmt);
    sqlite3_finalize(step_stmt);
    return true;
}

bool insert_recipe_row(sqlite3* db, Recipe& recipe, std::string& error) {
    sqlite3_stmt* stmt = nullptr;
    if (!prepare(db,
                 "INSERT INTO recipes (title, description, servings, "
                 "image_path, notes) VALUES (?, ?, ?, ?, ?);",
                 &stmt, error)) {
        return false;
    }
    bool ok = true;
    if (recipe.image_path.empty()) {
        if (sqlite3_bind_null(stmt, 4) != SQLITE_OK) {
            ok = false;
        }
    } else if (!bind_text(stmt, 4, recipe.image_path)) {
        ok = false;
    }
    if (ok && (!bind_text(stmt, 1, recipe.title) ||
               !bind_text(stmt, 2, recipe.description) ||
               sqlite3_bind_int(stmt, 3, recipe.servings) != SQLITE_OK ||
               !bind_text(stmt, 5, recipe.notes) ||
               !step_done(stmt, error, db))) {
        ok = false;
    }
    if (ok) {
        recipe.id = sqlite3_last_insert_rowid(db);
    }
    sqlite3_finalize(stmt);
    return ok;
}

bool insert_recipe(sqlite3* db, Recipe& recipe, std::string& error) {
    if (!exec_sql(db, "BEGIN;", error)) {
        return false;
    }
    bool ok = insert_recipe_row(db, recipe, error) &&
              insert_children(db, recipe, error);
    std::string tail_error;
    if (!exec_sql(db, ok ? "COMMIT;" : "ROLLBACK;", tail_error)) {
        if (ok) {
            error = tail_error;
            return false;
        }
    }
    return ok;
}

bool update_recipe(sqlite3* db, const Recipe& recipe, std::string& error) {
    if (!exec_sql(db, "BEGIN;", error)) {
        return false;
    }
    bool ok = true;
    sqlite3_stmt* stmt = nullptr;
    if (!prepare(db,
                 "UPDATE recipes SET title = ?, description = ?, "
                 "servings = ?, image_path = ?, notes = ? WHERE id = ?;",
                 &stmt, error)) {
        ok = false;
    }
    if (ok) {
        if (recipe.image_path.empty()) {
            if (sqlite3_bind_null(stmt, 4) != SQLITE_OK) {
                ok = false;
            }
        } else if (!bind_text(stmt, 4, recipe.image_path)) {
            ok = false;
        }
    }
    if (ok && (!bind_text(stmt, 1, recipe.title) ||
               !bind_text(stmt, 2, recipe.description) ||
               sqlite3_bind_int(stmt, 3, recipe.servings) != SQLITE_OK ||
               !bind_text(stmt, 5, recipe.notes) ||
               sqlite3_bind_int64(stmt, 6, recipe.id) != SQLITE_OK ||
               !step_done(stmt, error, db))) {
        ok = false;
    }
    sqlite3_finalize(stmt);
    if (ok) {
        // Delete the old children, then re-insert the draft's.
        sqlite3_stmt* del_ingredients = nullptr;
        sqlite3_stmt* del_steps = nullptr;
        if (!prepare(db, "DELETE FROM ingredients WHERE recipe_id = ?;",
                     &del_ingredients, error) ||
            !prepare(db, "DELETE FROM steps WHERE recipe_id = ?;",
                     &del_steps, error)) {
            ok = false;
        }
        if (ok) {
            sqlite3_bind_int64(del_ingredients, 1, recipe.id);
            if (!step_done(del_ingredients, error, db)) {
                ok = false;
            }
            sqlite3_bind_int64(del_steps, 1, recipe.id);
            if (ok && !step_done(del_steps, error, db)) {
                ok = false;
            }
        }
        sqlite3_finalize(del_ingredients);
        sqlite3_finalize(del_steps);
    }
    if (ok) {
        ok = insert_children(db, recipe, error);
    }
    std::string tail_error;
    if (!exec_sql(db, ok ? "COMMIT;" : "ROLLBACK;", tail_error)) {
        if (ok) {
            error = tail_error;
            return false;
        }
    }
    return ok;
}

bool delete_recipe(sqlite3* db, long long id, std::string& error) {
    sqlite3_stmt* stmt = nullptr;
    if (!prepare(db, "DELETE FROM recipes WHERE id = ?;", &stmt, error)) {
        return false;
    }
    sqlite3_bind_int64(stmt, 1, id);
    bool ok = step_done(stmt, error, db);
    sqlite3_finalize(stmt);
    return ok;
}

bool set_recipe_image(sqlite3* db, long long id, const std::string& path,
                      std::string& error) {
    sqlite3_stmt* stmt = nullptr;
    if (!prepare(db, "UPDATE recipes SET image_path = ? WHERE id = ?;",
                 &stmt, error)) {
        return false;
    }
    bool ok = true;
    if (path.empty()) {
        if (sqlite3_bind_null(stmt, 1) != SQLITE_OK) {
            ok = false;
        }
    } else if (!bind_text(stmt, 1, path)) {
        ok = false;
    }
    if (ok && (sqlite3_bind_int64(stmt, 2, id) != SQLITE_OK ||
               !step_done(stmt, error, db))) {
        ok = false;
    }
    sqlite3_finalize(stmt);
    return ok;
}
