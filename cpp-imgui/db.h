#pragma once

// SQLite storage for the recipe manager.
// Tables: recipes, ingredients, steps. The database file is
// recipes.db in the current working directory (git-ignored).
// On first run the tables are created and seeded with the same
// 3 recipes the hard-coded view used; later runs load from the
// database and do not re-seed.

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
    std::string image_path;
    std::vector<Ingredient> ingredients;
    std::vector<std::string> steps;
    std::string notes;
};

// Opens (creating if needed) the database at path. On failure
// returns false and sets error.
bool open_database(const std::string& path, sqlite3** db, std::string& error);

// Creates the tables if needed and seeds them once, only when
// the recipes table is empty. Returns false and sets error on failure.
bool init_and_seed(sqlite3* db, std::string& error);

// Loads all recipes, with ingredients and steps in position order.
// Returns false and sets error on failure.
bool load_recipes(sqlite3* db, std::vector<Recipe>& recipes, std::string& error);
