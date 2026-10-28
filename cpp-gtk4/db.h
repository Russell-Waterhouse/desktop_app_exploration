#pragma once

// SQLite storage for the recipe manager.
// Tables: recipes, ingredients, steps. The database file is
// recipes.db in the current working directory (git-ignored).
// On first run the tables are created and seeded with the same
// 3 recipes the hard-coded view used; later runs load from the
// database and do not re-seed. Foreign keys are on, so deleting
// a recipe removes its ingredients and steps.

#include <sqlite3.h>

#include <string>
#include <vector>

struct Ingredient {
    std::string amount;
    std::string unit;
    std::string name;
};

struct Recipe {
    long long id = 0;
    std::string title;
    std::string description;
    int servings = 0;
    // Empty means no image (stored as NULL in the database).
    std::string image_path;
    std::vector<Ingredient> ingredients;
    std::vector<std::string> steps;
    std::string notes;
};

// Opens (creating if needed) the database at path, with foreign
// keys enabled. On failure returns false and sets error.
bool open_database(const std::string& path, sqlite3** db, std::string& error);

// Creates the tables if needed and seeds them once, only when
// the recipes table is empty. Returns false and sets error on failure.
bool init_and_seed(sqlite3* db, std::string& error);

// Loads all recipes, with ingredients and steps in position order.
// Returns false and sets error on failure.
bool load_recipes(sqlite3* db, std::vector<Recipe>& recipes, std::string& error);

// Inserts a recipe (with its ingredients and steps) in one
// transaction and sets recipe.id to the new row id.
bool insert_recipe(sqlite3* db, Recipe& recipe, std::string& error);

// Replaces a recipe and all of its ingredients and steps, in one
// transaction. The image path is kept as stored on the recipe.
bool update_recipe(sqlite3* db, const Recipe& recipe, std::string& error);

// Deletes a recipe; its ingredients and steps go with it via
// ON DELETE CASCADE. Returns false and sets error on failure.
bool delete_recipe(sqlite3* db, long long id, std::string& error);

// Sets just a recipe's image path (NULL when path is empty).
bool set_recipe_image(sqlite3* db, long long id, const std::string& path,
                      std::string& error);
