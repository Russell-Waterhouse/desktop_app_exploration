#include "images.h"

#include <filesystem>
#include <system_error>

namespace fs = std::filesystem;

bool import_image(const std::string& source, std::string& dest, std::string& error) {
    std::error_code ec;
    fs::path source_path(source);
    std::string filename = source_path.filename().string();
    if (filename.empty()) {
        error = "Chosen file has no filename.";
        return false;
    }

    fs::path images_dir("images");
    fs::create_directories(images_dir, ec);
    if (ec) {
        error = "Could not create images directory: " + ec.message();
        return false;
    }

    fs::path candidate = images_dir / filename;
    if (candidate == source_path) {
        // Already the stored copy: nothing to do.
        dest = candidate.string();
        return true;
    }
    if (fs::exists(candidate)) {
        std::string stem = source_path.stem().string();
        std::string extension = source_path.extension().string();
        int counter = 1;
        while (true) {
            std::string candidate_name = stem + "_" + std::to_string(counter) + extension;
            candidate = images_dir / candidate_name;
            if (!fs::exists(candidate)) {
                break;
            }
            ++counter;
        }
    }
    fs::copy_file(source_path, candidate, ec);
    if (ec) {
        error = "Could not copy image: " + ec.message();
        return false;
    }
    dest = candidate.string();
    return true;
}
