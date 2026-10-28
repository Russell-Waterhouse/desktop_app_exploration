#include "db.h"

#include <sqlite3.h>

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
    const unsigned char* text = sqlite3_column_text(stmt, column);
    return text != nullptr ? reinterpret_cast<const char*>(text) : "";
}

bool bind_text(sqlite3_stmt* stmt, int index, const std::string& value) {
    return sqlite3_bind_text(stmt, index, value.c_str(), -1, SQLITE_TRANSIENT) ==
           SQLITE_OK;
}

// Binds NULL for an empty value, matching rust-egui, which stores
// NULL (not "") for a recipe with no image.
bool bind_text_or_null(sqlite3_stmt* stmt, int index, const std::string& value) {
    if (value.empty()) {
        return sqlite3_bind_null(stmt, index) == SQLITE_OK;
    }
    return bind_text(stmt, index, value);
}

bool step_done(sqlite3_stmt* stmt, std::string& error, sqlite3* db) {
    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        error = sqlite3_errmsg(db);
        return false;
    }
    return true;
}

// Seed data: the same 3 recipes the hard-coded view used.
// (A later step will move this into its own seed file, as rust-egui did.)
std::vector<Recipe> seed_recipes() {
    return {
        {
            0,
            "Banana Bread",
            "A classic loaf, best with very ripe bananas.",
            8,
            "",
            {
                {"3", "", "ripe bananas, mashed"},
                {"1/2", "cup", "butter, melted"},
                {"3/4", "cup", "sugar"},
                {"1", "", "egg"},
                {"1", "tsp", "vanilla"},
                {"1", "tsp", "baking soda"},
                {"1 1/2", "cups", "flour"},
            },
            {
                "Preheat the oven to 350°F and grease a 9x5 loaf pan.",
                "Mash the bananas, then stir in the melted butter, sugar, egg, and vanilla.",
                "Stir in the baking soda and flour until just combined.",
                "Pour into the pan and bake for 55-65 minutes, until a toothpick comes out clean.",
                "Cool in the pan for 10 minutes, then turn out onto a rack.",
            },
            "Optional: fold in walnuts or chocolate chips before baking.",
        },
        {
            0,
            "Tomato Basil Pasta",
            "A quick weeknight pasta with fresh tomatoes and basil.",
            4,
            "",
            {
                {"12", "oz", "pasta"},
                {"2", "lbs", "tomatoes, chopped"},
                {"3", "cloves", "garlic, sliced"},
                {"1/4", "cup", "olive oil"},
                {"1", "cup", "basil leaves"},
                {"1/2", "cup", "parmesan, grated"},
            },
            {
                "Cook the pasta in salted water until al dente, reserving a cup of pasta water.",
                "Meanwhile, warm the olive oil and garlic until fragrant, about 2 minutes.",
                "Add the tomatoes and cook until they soften, about 8 minutes.",
                "Toss the pasta with the sauce, basil, and parmesan, adding pasta water as needed.",
            },
            "Serve immediately, with extra parmesan on top.",
        },
        {
            0,
            "Chicken Stir Fry",
            "Chicken and vegetables in a simple soy-ginger sauce, served with rice.",
            4,
            "",
            {
                {"1 1/2", "lbs", "chicken breast, sliced"},
                {"2", "", "bell peppers, sliced"},
                {"2", "cups", "broccoli florets"},
                {"3", "tbsp", "soy sauce"},
                {"1", "tbsp", "ginger, grated"},
                {"2", "cloves", "garlic, minced"},
            },
            {
                "Sear the chicken in a hot, oiled pan until cooked through, then set aside.",
                "Stir fry the peppers and broccoli until just tender, about 4 minutes.",
                "Return the chicken to the pan with the soy sauce, ginger, and garlic.",
                "Cook for 2 more minutes, stirring, until the sauce coats everything.",
            },
            "Serve over rice.",
        },
    };
}

bool insert_seed(sqlite3* db, std::string& error) {
    if (!exec_sql(db, "BEGIN;", error)) {
        return false;
    }

    sqlite3_stmt* recipe_stmt = nullptr;
    sqlite3_stmt* ingredient_stmt = nullptr;
    sqlite3_stmt* step_stmt = nullptr;
    bool ok = true;

    if (sqlite3_prepare_v2(db,
                           "INSERT INTO recipes (title, description, servings, "
                           "image_path, notes) "
                           "VALUES (?, ?, ?, NULL, ?);",
                           -1, &recipe_stmt, nullptr) != SQLITE_OK ||
        sqlite3_prepare_v2(db,
                           "INSERT INTO ingredients (recipe_id, position, amount, "
                           "unit, name) VALUES (?, ?, ?, ?, ?);",
                           -1, &ingredient_stmt, nullptr) != SQLITE_OK ||
        sqlite3_prepare_v2(db,
                           "INSERT INTO steps (recipe_id, position, text) "
                           "VALUES (?, ?, ?);",
                           -1, &step_stmt, nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
        ok = false;
    }

    if (ok) {
        for (const Recipe& recipe : seed_recipes()) {
            sqlite3_reset(recipe_stmt);
            sqlite3_clear_bindings(recipe_stmt);
            if (!bind_text(recipe_stmt, 1, recipe.title) ||
                !bind_text(recipe_stmt, 2, recipe.description) ||
                sqlite3_bind_int(recipe_stmt, 3, recipe.servings) != SQLITE_OK ||
                !bind_text(recipe_stmt, 4, recipe.notes) ||
                !step_done(recipe_stmt, error, db)) {
                ok = false;
                break;
            }
            long long recipe_id = sqlite3_last_insert_rowid(db);

            for (int i = 0; i < static_cast<int>(recipe.ingredients.size()) && ok; ++i) {
                const Ingredient& ingredient = recipe.ingredients[i];
                sqlite3_reset(ingredient_stmt);
                sqlite3_clear_bindings(ingredient_stmt);
                if (sqlite3_bind_int64(ingredient_stmt, 1, recipe_id) != SQLITE_OK ||
                    sqlite3_bind_int(ingredient_stmt, 2, i) != SQLITE_OK ||
                    !bind_text(ingredient_stmt, 3, ingredient.amount) ||
                    !bind_text(ingredient_stmt, 4, ingredient.unit) ||
                    !bind_text(ingredient_stmt, 5, ingredient.name) ||
                    !step_done(ingredient_stmt, error, db)) {
                    ok = false;
                }
            }
            for (int i = 0; i < static_cast<int>(recipe.steps.size()) && ok; ++i) {
                sqlite3_reset(step_stmt);
                sqlite3_clear_bindings(step_stmt);
                if (sqlite3_bind_int64(step_stmt, 1, recipe_id) != SQLITE_OK ||
                    sqlite3_bind_int(step_stmt, 2, i) != SQLITE_OK ||
                    !bind_text(step_stmt, 3, recipe.steps[i]) ||
                    !step_done(step_stmt, error, db)) {
                    ok = false;
                }
            }
            if (!ok) {
                break;
            }
        }
    }

    sqlite3_finalize(recipe_stmt);
    sqlite3_finalize(ingredient_stmt);
    sqlite3_finalize(step_stmt);

    std::string tail_error;
    if (!exec_sql(db, ok ? "COMMIT;" : "ROLLBACK;", tail_error)) {
        if (ok) {
            error = tail_error;
            return false;
        }
    }
    return ok;
}

bool delete_children(sqlite3* db, long long recipe_id, std::string& error) {
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db, "DELETE FROM ingredients WHERE recipe_id = ?;",
                           -1, &stmt, nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
        return false;
    }
    sqlite3_bind_int64(stmt, 1, recipe_id);
    bool ok = step_done(stmt, error, db);
    sqlite3_finalize(stmt);
    if (!ok) {
        return false;
    }
    if (sqlite3_prepare_v2(db, "DELETE FROM steps WHERE recipe_id = ?;",
                           -1, &stmt, nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
        return false;
    }
    sqlite3_bind_int64(stmt, 1, recipe_id);
    ok = step_done(stmt, error, db);
    sqlite3_finalize(stmt);
    return ok;
}

bool insert_children(sqlite3* db, long long recipe_id, const Recipe& recipe,
                     std::string& error) {
    sqlite3_stmt* ingredient_stmt = nullptr;
    sqlite3_stmt* step_stmt = nullptr;
    bool ok = true;

    if (sqlite3_prepare_v2(db,
                           "INSERT INTO ingredients (recipe_id, position, amount, "
                           "unit, name) VALUES (?, ?, ?, ?, ?);",
                           -1, &ingredient_stmt, nullptr) != SQLITE_OK ||
        sqlite3_prepare_v2(db,
                           "INSERT INTO steps (recipe_id, position, text) "
                           "VALUES (?, ?, ?);",
                           -1, &step_stmt, nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
        ok = false;
    }

    if (ok) {
        for (int i = 0; i < static_cast<int>(recipe.ingredients.size()) && ok; ++i) {
            const Ingredient& ingredient = recipe.ingredients[i];
            sqlite3_reset(ingredient_stmt);
            sqlite3_clear_bindings(ingredient_stmt);
            if (sqlite3_bind_int64(ingredient_stmt, 1, recipe_id) != SQLITE_OK ||
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
            if (sqlite3_bind_int64(step_stmt, 1, recipe_id) != SQLITE_OK ||
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

// Runs body inside a transaction: BEGIN, then COMMIT on success
// or ROLLBACK on failure. body returns false (with error set) on
// failure.
template <typename Body>
bool in_transaction(sqlite3* db, Body body, std::string& error) {
    if (!exec_sql(db, "BEGIN;", error)) {
        return false;
    }
    bool ok = body();
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

bool insert_recipe(sqlite3* db, const Recipe& recipe, long long& new_id,
                   std::string& error) {
    return in_transaction(db, [&]() {
        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(db,
                               "INSERT INTO recipes (title, description, servings, "
                               "image_path, notes) VALUES (?, ?, ?, ?, ?);",
                               -1, &stmt, nullptr) != SQLITE_OK) {
            error = sqlite3_errmsg(db);
            return false;
        }
        bool ok = true;
        if (!bind_text(stmt, 1, recipe.title) ||
            !bind_text(stmt, 2, recipe.description) ||
            sqlite3_bind_int(stmt, 3, recipe.servings) != SQLITE_OK ||
            !bind_text_or_null(stmt, 4, recipe.image_path) ||
            !bind_text(stmt, 5, recipe.notes) ||
            !step_done(stmt, error, db)) {
            ok = false;
        }
        sqlite3_finalize(stmt);
        if (!ok) {
            return false;
        }
        new_id = sqlite3_last_insert_rowid(db);
        return insert_children(db, new_id, recipe, error);
    }, error);
}

bool update_recipe(sqlite3* db, const Recipe& recipe, std::string& error) {
    return in_transaction(db, [&]() {
        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(db,
                               "UPDATE recipes SET title = ?, description = ?, "
                               "servings = ?, image_path = ?, notes = ? "
                               "WHERE id = ?;",
                               -1, &stmt, nullptr) != SQLITE_OK) {
            error = sqlite3_errmsg(db);
            return false;
        }
        bool ok = true;
        if (!bind_text(stmt, 1, recipe.title) ||
            !bind_text(stmt, 2, recipe.description) ||
            sqlite3_bind_int(stmt, 3, recipe.servings) != SQLITE_OK ||
            !bind_text_or_null(stmt, 4, recipe.image_path) ||
            !bind_text(stmt, 5, recipe.notes) ||
            sqlite3_bind_int64(stmt, 6, recipe.id) != SQLITE_OK ||
            !step_done(stmt, error, db)) {
            ok = false;
        }
        sqlite3_finalize(stmt);
        if (!ok) {
            return false;
        }
        // Children are deleted and re-inserted, as in rust-egui.
        return delete_children(db, recipe.id, error) &&
               insert_children(db, recipe.id, recipe, error);
    }, error);
}

bool delete_recipe(sqlite3* db, long long id, std::string& error) {
    return in_transaction(db, [&]() {
        if (!delete_children(db, id, error)) {
            return false;
        }
        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(db, "DELETE FROM recipes WHERE id = ?;",
                               -1, &stmt, nullptr) != SQLITE_OK) {
            error = sqlite3_errmsg(db);
            return false;
        }
        sqlite3_bind_int64(stmt, 1, id);
        bool ok = step_done(stmt, error, db);
        sqlite3_finalize(stmt);
        return ok;
    }, error);
}

bool open_database(const std::string& path, sqlite3** db, std::string& error) {
    if (sqlite3_open(path.c_str(), db) != SQLITE_OK) {
        error = *db != nullptr ? sqlite3_errmsg(*db) : "Could not open database";
        if (*db != nullptr) {
            sqlite3_close(*db);
            *db = nullptr;
        }
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
                  "recipe_id INTEGER NOT NULL, "
                  "position INTEGER NOT NULL, "
                  "amount TEXT NOT NULL, "
                  "unit TEXT NOT NULL, "
                  "name TEXT NOT NULL);",
                  error) ||
        !exec_sql(db,
                  "CREATE TABLE IF NOT EXISTS steps ("
                  "id INTEGER PRIMARY KEY, "
                  "recipe_id INTEGER NOT NULL, "
                  "position INTEGER NOT NULL, "
                  "text TEXT NOT NULL);",
                  error)) {
        return false;
    }

    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM recipes;", -1, &stmt,
                           nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
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
    if (sqlite3_prepare_v2(db,
                           "SELECT id, title, description, servings, "
                           "image_path, notes FROM recipes ORDER BY id;",
                           -1, &stmt, nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
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
    if (sqlite3_prepare_v2(db,
                           "SELECT amount, unit, name FROM ingredients "
                           "WHERE recipe_id = ? ORDER BY position;",
                           -1, &ingredient_stmt, nullptr) != SQLITE_OK ||
        sqlite3_prepare_v2(db,
                           "SELECT text FROM steps WHERE recipe_id = ? "
                           "ORDER BY position;",
                           -1, &step_stmt, nullptr) != SQLITE_OK) {
        error = sqlite3_errmsg(db);
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
