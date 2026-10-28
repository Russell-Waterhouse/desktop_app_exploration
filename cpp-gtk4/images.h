#pragma once

// Image files on disk.
//
// A recipe's image_path is a path to a file, usually a copy inside
// the images/ directory next to recipes.db. Importing copies the
// chosen file there, so the recipe keeps working if the original
// file is later moved or deleted. It never overwrites an existing
// file: a second import of the same filename gets a _1, _2 suffix.

#include <string>

// Copies source into images/ and returns the stored path
// (for example "images/photo.png"). On failure returns false
// and sets error.
bool import_image(const std::string& source, std::string& dest, std::string& error);
