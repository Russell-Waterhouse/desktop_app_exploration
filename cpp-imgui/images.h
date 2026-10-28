#pragma once

// Image files on disk, plus asynchronous image loading.
//
// Importing copies the chosen file into images/ next to recipes.db,
// so the recipe keeps working if the original file is later moved
// or deleted. It never overwrites an existing file: a second import
// of the same filename gets a _1, _2 suffix (same rule as rust-egui).
//
// Loading is split across threads the way rust-egui does it:
// decoding (stb_image) runs on a worker thread per image, and the
// OpenGL texture is created on the main thread only, from the
// decoded pixels, when poll() sees the decode has finished. While
// a path is still decoding, the UI shows a loading spinner for it
// instead of an image, and the interface stays responsive. A path
// that fails to decode is remembered as failed, so it is not
// retried every frame.

#include <memory>
#include <string>
#include <vector>

#include <SDL_opengl.h>

struct ImDrawList;

// Copies source into images/ and returns the stored path
// (e.g. "images/photo.png"). On failure returns "" and sets error.
// A file already inside images/ is used as-is, not copied again.
std::string import_image(const std::string& source, std::string& error);

// Draws a rotating spinner arc (like egui's Spinner) centred at
// center with the given radius. Call from the main thread during
// rendering; time_seconds should advance every frame (ImGui::GetTime).
void draw_spinner(ImDrawList* draw_list, float center_x, float center_y,
                  float radius, float time_seconds, unsigned int color);

// Aspect-preserving fit of (width, height) inside (max_width,
// max_height). Returns the size to draw the image at.
void fit_image_size(int width, int height, float max_width, float max_height,
                    float& out_width, float& out_height);

class ImageLoader {
public:
    enum class State { Loading, Ready, Failed };

    ImageLoader() = default;
    ImageLoader(const ImageLoader&) = delete;
    ImageLoader& operator=(const ImageLoader&) = delete;

    // Starts decoding path on a worker thread, unless it is already
    // cached, failed, or loading. Safe to call every frame.
    void request(const std::string& path);

    // Non-blocking: turns finished decodes into OpenGL textures.
    // Must be called on the main thread, every frame, while the
    // OpenGL context is current.
    void poll();

    // Current state of a path. A path never requested counts as
    // Loading (the caller requests every visible path each frame).
    State state(const std::string& path) const;

    // OpenGL texture for a Ready path, or 0 otherwise.
    GLuint texture(const std::string& path) const;

    // Pixel size of a Ready path's image, or false if not Ready.
    bool texture_size(const std::string& path, int& width, int& height) const;

    // Deletes all textures. Call on the main thread before the
    // OpenGL context is destroyed.
    void clear();

    ~ImageLoader();

private:
    struct Job;
    struct Texture {
        GLuint id = 0;
        int width = 0;
        int height = 0;
    };

    // Jobs still decoding (or finished but not yet textured).
    // Jobs are shared with their worker threads, so a detached
    // thread can outlive the loader without touching freed memory;
    // only the pixel buffer and flags live in the job, never a
    // pointer back to the loader.
    std::vector<std::pair<std::string, std::shared_ptr<Job>>> jobs_;
    std::vector<std::pair<std::string, Texture>> textures_;
    std::vector<std::string> failures_;
};
