#pragma once

// Shaped text rendering for Dear ImGui (the "KB plan").
//
// Dear ImGui's own text path looks glyphs up by codepoint, so it
// cannot shape Arabic or Devanagari, and its default font renders
// Chinese and emoji as '?'. This module shapes strings with
// kb_text_shape (vendored in third_party/, zlib license), draws
// outline glyphs with stb_truetype (already fetched for
// stb_image), and draws color emoji with FreeType from the
// system Noto Color Emoji font (CBDT bitmaps, which
// stb_truetype cannot rasterize). Each shaped line is baked
// once into an OpenGL texture and cached, then drawn with
// ImGui::Image, so per-frame cost is one image per line.
//
// Fonts are resolved with fontconfig (Noto Sans, Noto Sans
// Arabic, Noto Sans Devanagari, Noto Sans CJK SC, Noto Color
// Emoji), with hardcoded /usr/share/fonts fallbacks when
// fontconfig finds nothing. The emoji font is pushed first
// (bottom of kb's font stack) so shared codepoints (spaces,
// digits, Latin) resolve to the other fonts.
//
// Display-only: stored recipe data stays logical-order UTF-8,
// and the add/edit forms keep ImGui's unshaped InputText (text
// input shaping is a separate todo item). When initialization
// fails (no usable fonts), all Draw functions fall back to
// plain ImGui::Text rendering instead of breaking the app.
//
// Call InitShapedText after the OpenGL context exists (textures
// are created on first draw) and ShutdownShapedText while it is
// still current, before the context is destroyed.

#include <string>

struct ShapedLineTexture {
    unsigned int id = 0;  // OpenGL texture, 0 when nothing to draw
    float width = 0.0f;
    float height = 0.0f;
};

// Builds the font setup. Returns false (with error set) when not
// even the Latin font could be loaded; the caller then uses
// plain ImGui::Text everywhere.
bool InitShapedText(std::string& error);

// Frees all cached textures and font state. Call on the main
// thread while the OpenGL context is still current.
void ShutdownShapedText();

// Bakes (or reuses the cached bake of) one logical line of text
// at pixel_height. Returns false when shaped rendering is
// unavailable or the line is empty.
bool GetShapedLine(const std::string& text, float pixel_height,
                   ShapedLineTexture& out);

// Single-line shaped text at the current cursor position, like
// ImGui::Text but shaped. Falls back to ImGui::Text when shaped
// rendering is unavailable.
void DrawShapedText(const std::string& text, float pixel_height);

// Wrapped shaped text, like ImGui::TextWrapped but shaped.
// wrap_width is the available width for each line, measured
// from the current cursor position. Hard newlines in the text
// force line breaks. Falls back to ImGui::TextWrapped when
// shaped rendering is unavailable.
void DrawShapedWrapped(const std::string& text, float pixel_height,
                       float wrap_width);
