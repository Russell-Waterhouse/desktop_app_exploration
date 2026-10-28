#pragma once

// Seed data only: inserted once, when the recipes table is empty.
// After that the app loads from the database, not from this file.

#include "db.h"

#include <vector>

std::vector<Recipe> seed_recipes();
