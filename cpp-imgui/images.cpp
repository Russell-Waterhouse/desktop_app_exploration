#include "images.h"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <mutex>
#include <thread>

#include "imgui.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

namespace fs = std::filesystem;

namespace {

// True when any (path, value) pair in items has the given path.
// Templated so it works for the loader's private Texture type too.
template <typename Pair>
bool path_in(const std::vector<Pair>& items, const std::string& path) {
    return std::any_of(items.begin(), items.end(),
                       [&](const auto& item) { return item.first == path; });
}

}  // namespace

std::string import_image(const std::string& source, std::string& error) {
    fs::path source_path(source);
    std::string filename = source_path.filename().string();
    if (filename.empty()) {
        error = "Chosen file has no filename.";
        return "";
    }

    std::error_code ec;
    fs::create_directories("images", ec);
    if (ec) {
        error = "Could not create images directory: " + ec.message();
        return "";
    }

    fs::path dest = fs::path("images") / filename;
    // Already the stored copy: nothing to do.
    if (dest == source_path) {
        return dest.string();
    }
    if (fs::exists(dest)) {
        std::string stem = source_path.stem().string();
        if (stem.empty()) {
            stem = "image";
        }
        std::string extension = source_path.extension().string();
        int counter = 1;
        while (true) {
            std::string candidate_name = stem + "_" + std::to_string(counter) + extension;
            fs::path candidate = fs::path("images") / candidate_name;
            if (!fs::exists(candidate)) {
                fs::copy_file(source_path, candidate, ec);
                if (ec) {
                    error = "Could not copy image: " + ec.message();
                    return "";
                }
                return candidate.string();
            }
            ++counter;
        }
    }
    fs::copy_file(source_path, dest, ec);
    if (ec) {
        error = "Could not copy image: " + ec.message();
        return "";
    }
    return dest.string();
}

void draw_spinner(ImDrawList* draw_list, float center_x, float center_y,
                  float radius, float time_seconds, unsigned int color) {
    // A 240-degree arc rotating once per second, like egui's Spinner.
    const float start = time_seconds * 2.0f * 3.14159265f;
    const float end = start + 4.18879020f;  // 240 degrees in radians
    draw_list->PathArcTo(ImVec2(center_x, center_y), radius, start, end, 24);
    draw_list->PathStroke(color, 0, 2.5f);
}

void fit_image_size(int width, int height, float max_width, float max_height,
                    float& out_width, float& out_height) {
    if (width <= 0 || height <= 0) {
        out_width = max_width;
        out_height = max_height;
        return;
    }
    float scale = std::min(max_width / static_cast<float>(width),
                           max_height / static_cast<float>(height));
    out_width = static_cast<float>(width) * scale;
    out_height = static_cast<float>(height) * scale;
}

struct ImageLoader::Job {
    std::mutex mutex;
    bool done = false;
    bool ok = false;
    int width = 0;
    int height = 0;
    // Decoded RGBA pixels, row-major. Only touched by the worker
    // thread until done is set (under mutex); the main thread reads
    // them in poll() after seeing done.
    std::vector<unsigned char> pixels;
};

void ImageLoader::request(const std::string& path) {
    if (path.empty()) {
        return;
    }
    if (path_in(textures_, path) ||
        std::find(failures_.begin(), failures_.end(), path) != failures_.end()) {
        return;
    }
    for (const auto& job : jobs_) {
        if (job.first == path) {
            return;
        }
    }
    auto job = std::make_shared<Job>();
    jobs_.push_back({path, job});
    std::thread([job, path]() {
        int width = 0;
        int height = 0;
        int channels = 0;
        // Force 4 channels (RGBA): the texture upload below always
        // uses GL_RGBA, whatever the file's native channel count.
        unsigned char* data = stbi_load(path.c_str(), &width, &height, &channels, 4);
        std::lock_guard<std::mutex> lock(job->mutex);
        if (data != nullptr) {
            size_t size = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
            job->pixels.assign(data, data + size);
            job->width = width;
            job->height = height;
            job->ok = true;
            stbi_image_free(data);
        }
        job->done = true;
    }).detach();
}

void ImageLoader::poll() {
    std::vector<std::pair<std::string, std::shared_ptr<Job>>> remaining;
    for (auto& entry : jobs_) {
        bool done = false;
        bool ok = false;
        int width = 0;
        int height = 0;
        std::vector<unsigned char> pixels;
        {
            std::lock_guard<std::mutex> lock(entry.second->mutex);
            done = entry.second->done;
            ok = entry.second->ok;
            width = entry.second->width;
            height = entry.second->height;
            if (done && ok) {
                pixels = std::move(entry.second->pixels);
            }
        }
        if (!done) {
            remaining.push_back(entry);
            continue;
        }
        if (!ok) {
            failures_.push_back(entry.first);
            continue;
        }
        // Texture creation must happen on the main thread, while
        // the OpenGL context is current: this is that thread.
        GLuint texture_id = 0;
        glGenTextures(1, &texture_id);
        glBindTexture(GL_TEXTURE_2D, texture_id);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, pixels.data());
        textures_.push_back({entry.first, Texture{texture_id, width, height}});
    }
    jobs_ = std::move(remaining);
}

ImageLoader::State ImageLoader::state(const std::string& path) const {
    if (path_in(textures_, path)) {
        return State::Ready;
    }
    if (std::find(failures_.begin(), failures_.end(), path) != failures_.end()) {
        return State::Failed;
    }
    return State::Loading;
}

GLuint ImageLoader::texture(const std::string& path) const {
    for (const auto& item : textures_) {
        if (item.first == path) {
            return item.second.id;
        }
    }
    return 0;
}

bool ImageLoader::texture_size(const std::string& path, int& width, int& height) const {
    for (const auto& item : textures_) {
        if (item.first == path) {
            width = item.second.width;
            height = item.second.height;
            return true;
        }
    }
    return false;
}

void ImageLoader::clear() {
    for (const auto& item : textures_) {
        glDeleteTextures(1, &item.second.id);
    }
    textures_.clear();
    failures_.clear();
    // Jobs are shared with their worker threads; dropping the
    // loader's references here does not free a job a thread is
    // still writing to. Jobs still in flight are simply never
    // textured, since poll() will not run again.
    jobs_.clear();
}

ImageLoader::~ImageLoader() {
    // Textures must be deleted while the context is current; the
    // app calls clear() explicitly before tearing the context down.
    // If it did not, deleting here would run after context teardown
    // and be a no-op at best, so nothing is done here on purpose.
}
