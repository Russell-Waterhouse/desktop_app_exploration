// Shaped text rendering: kb shaping + stb outlines + FreeType
// color emoji, baked per line into cached OpenGL textures.
//
// kb_text_shape is a single header (v2.28g, commit 7d811ad,
// vendored in third_party/); stb_truetype comes from the stb
// FetchContent already used for stb_image. One translation unit
// defines both implementations here, so no other file includes
// either header with its implementation macro.

#define KB_TEXT_SHAPE_IMPLEMENTATION
#include "third_party/kb_text_shape.h"
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include <SDL_opengl.h>
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "imgui.h"
#include "shaped_layout.h"
#include "shaped_text.h"

namespace {

struct Font {
    std::string path;
    int index = 0;
    kbts_font* kb = nullptr;
    stbtt_fontinfo stb;
    bool stb_ok = false;
    unsigned char* data = nullptr;
    bool is_emoji = false;
    FT_Face ft_face = nullptr;
    int hhea_asc = 0;
    int hhea_desc = 0;
};

kbts_shape_context* g_ctx = nullptr;
FT_Library g_ft = nullptr;
std::vector<Font> g_fonts;
bool g_ok = false;

struct CachedLine {
    GLuint id = 0;
    float width = 0.0f;
    float height = 0.0f;
};

std::map<std::string, CachedLine> g_line_cache;
std::map<std::string, std::vector<CachedLine>> g_wrapped_cache;

void ClearCache() {
    for (const auto& entry : g_line_cache) {
        if (entry.second.id != 0) glDeleteTextures(1, &entry.second.id);
    }
    g_line_cache.clear();
    for (const auto& entry : g_wrapped_cache) {
        for (const CachedLine& line : entry.second) {
            if (line.id != 0) glDeleteTextures(1, &line.id);
        }
    }
    g_wrapped_cache.clear();
}

unsigned char* ReadFile(const char* path, long* out_size) {
    FILE* f = fopen(path, "rb");
    if (!f) return nullptr;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char* data = (unsigned char*)malloc(static_cast<size_t>(n));
    if (fread(data, 1, static_cast<size_t>(n), f) != static_cast<size_t>(n)) {
        fclose(f);
        free(data);
        return nullptr;
    }
    fclose(f);
    *out_size = n;
    return data;
}

// Reads hhea ascent/descent straight from the sfnt table
// directory. Needed for the emoji font: FreeType reports
// ascender/descender as 0 for this bitmap-only font, and
// stb_truetype refuses to init it (no glyf table).
bool ReadHhea(const char* path, int* asc, int* desc) {
    FILE* f = fopen(path, "rb");
    if (!f) return false;
    unsigned char hdr[12];
    if (fread(hdr, 1, 12, f) != 12) { fclose(f); return false; }
    int num_tables = (hdr[4] << 8) | hdr[5];
    for (int i = 0; i < num_tables; ++i) {
        unsigned char rec[16];
        if (fread(rec, 1, 16, f) != 16) { fclose(f); return false; }
        if (memcmp(rec, "hhea", 4) == 0) {
            unsigned long off = (static_cast<unsigned long>(rec[8]) << 24) |
                                (static_cast<unsigned long>(rec[9]) << 16) |
                                (static_cast<unsigned long>(rec[10]) << 8) | rec[11];
            fseek(f, static_cast<long>(off), SEEK_SET);
            unsigned char h[8];
            if (fread(h, 1, 8, f) != 8) { fclose(f); return false; }
            auto s16 = [](unsigned char* p) -> int {
                int v = (p[0] << 8) | p[1];
                return v >= 32768 ? v - 65536 : v;
            };
            *asc = s16(h + 4);
            *desc = s16(h + 6);
            fclose(f);
            return true;
        }
    }
    fclose(f);
    return false;
}

bool ResolveFont(const char* family, std::string& path, int& index) {
    FcInit();
    FcPattern* pat = FcPatternCreate();
    FcPatternAddString(pat, FC_FAMILY, reinterpret_cast<const FcChar8*>(family));
    FcConfigSubstitute(nullptr, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);
    FcResult res = FcResultNoMatch;
    FcPattern* match = FcFontMatch(nullptr, pat, &res);
    bool ok = false;
    if (match != nullptr) {
        FcChar8* file = nullptr;
        if (FcPatternGetString(match, FC_FILE, 0, &file) == FcResultMatch) {
            path = reinterpret_cast<const char*>(file);
            ok = true;
        }
        int idx = 0;
        if (FcPatternGetInteger(match, FC_INDEX, 0, &idx) == FcResultMatch) {
            index = idx;
        }
        FcPatternDestroy(match);
    }
    FcPatternDestroy(pat);
    return ok;
}

// Hardcoded fallbacks when fontconfig finds nothing. Ubuntu and
// Fedora paths differ (truetype/noto vs google-noto), so both
// are tried; the CJK collection index is 2 (SC face) on both.
bool FallbackFont(const char* family, std::string& path, int& index) {
    static const std::pair<const char*, const char*> kCandidates[] = {
        {"Noto Sans", "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"},
        {"Noto Sans", "/usr/share/fonts/google-noto/NotoSans-Regular.ttf"},
        {"Noto Sans", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"},
        {"Noto Sans Arabic", "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf"},
        {"Noto Sans Arabic", "/usr/share/fonts/google-noto/NotoSansArabic-Regular.ttf"},
        {"Noto Sans Devanagari", "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf"},
        {"Noto Sans Devanagari", "/usr/share/fonts/google-noto/NotoSansDevanagari-Regular.ttf"},
        {"Noto Sans CJK SC", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"},
        {"Noto Sans CJK SC", "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc"},
        {"Noto Color Emoji", "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"},
        {"Noto Color Emoji", "/usr/share/fonts/google-noto-color-emoji/NotoColorEmoji.ttf"},
    };
    for (const auto& cand : kCandidates) {
        if (std::string(family) != cand.first) continue;
        FILE* f = fopen(cand.second, "rb");
        if (f != nullptr) {
            fclose(f);
            path = cand.second;
            index = std::string(family) == "Noto Sans CJK SC" ? 2 : 0;
            return true;
        }
    }
    return false;
}

bool LoadFont(const char* family, bool is_emoji, bool required, std::string& error) {
    std::string path;
    int index = 0;
    if (!ResolveFont(family, path, index) && !FallbackFont(family, path, index)) {
        if (required) error = std::string("shaped text: font not found: ") + family;
        fprintf(stderr, "shaped text: font not found: %s\n", family);
        return false;
    }
    Font font;
    font.path = path;
    font.index = index;
    font.is_emoji = is_emoji;
    long size = 0;
    font.data = ReadFile(path.c_str(), &size);
    if (font.data == nullptr) {
        if (required) error = std::string("shaped text: cannot read font: ") + path;
        fprintf(stderr, "shaped text: cannot read font: %s\n", path.c_str());
        return false;
    }
    if (is_emoji) {
        if (FT_New_Face(g_ft, path.c_str(), 0, &font.ft_face) != 0) {
            if (required) error = std::string("shaped text: FreeType cannot open: ") + path;
            fprintf(stderr, "shaped text: FreeType cannot open: %s\n", path.c_str());
            free(font.data);
            return false;
        }
        if (font.ft_face->num_fixed_sizes > 0) FT_Select_Size(font.ft_face, 0);
        if (!ReadHhea(path.c_str(), &font.hhea_asc, &font.hhea_desc) ||
            font.hhea_asc == font.hhea_desc) {
            if (required) error = std::string("shaped text: no hhea metrics: ") + path;
            fprintf(stderr, "shaped text: no hhea metrics: %s\n", path.c_str());
            FT_Done_Face(font.ft_face);
            free(font.data);
            return false;
        }
    } else {
        int offset = stbtt_GetFontOffsetForIndex(font.data, index);
        if (offset < 0 || stbtt_InitFont(&font.stb, font.data, offset) == 0) {
            if (required) error = std::string("shaped text: stb cannot open: ") + path;
            fprintf(stderr, "shaped text: stb cannot open: %s\n", path.c_str());
            free(font.data);
            return false;
        }
        font.stb_ok = true;
    }
    font.kb = kbts_ShapePushFontFromFile(g_ctx, path.c_str(), index);
    if (font.kb == nullptr) {
        if (required) error = std::string("shaped text: kb cannot open: ") + path;
        fprintf(stderr, "shaped text: kb cannot open: %s\n", path.c_str());
        if (font.ft_face != nullptr) FT_Done_Face(font.ft_face);
        free(font.data);
        return false;
    }
    g_fonts.push_back(font);
    return true;
}

int FontIndexFor(kbts_font* kb) {
    for (int i = 0; i < static_cast<int>(g_fonts.size()); ++i) {
        if (g_fonts[i].kb == kb) return i;
    }
    return -1;
}

bool IsCjk(uint32_t cp) {
    return (cp >= 0x3400 && cp <= 0x4DBF) || (cp >= 0x4E00 && cp <= 0x9FFF) ||
           (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xAC00 && cp <= 0xD7A3) ||
           (cp >= 0x20000 && cp <= 0x2FA1F);
}

// One shaped paragraph: runs from kb, converted to the layout
// module's runs (glyph advances in pixels at pixel_height).

struct ShapedGlyphInfo {
    int font = -1;
    int id = 0;
    float off_x = 0.0f;
    float off_y = 0.0f;
};

struct ShapedParagraph {
    bool rtl = false;
    std::vector<shaped_layout::Run> runs;
    // infos[run][glyph], parallel to runs[][].glyphs (shaped order).
    std::vector<std::vector<ShapedGlyphInfo>> infos;
};

bool ShapeParagraph(const std::string& text, float pixel_height,
                    ShapedParagraph& out) {
    kbts_ShapeBegin(g_ctx, KBTS_DIRECTION_DONT_KNOW, KBTS_LANGUAGE_DONT_KNOW);
    kbts_ShapeUtf8(g_ctx, text.c_str(), static_cast<int>(text.size()),
                   KBTS_USER_ID_GENERATION_MODE_CODEPOINT_INDEX);
    kbts_ShapeEnd(g_ctx);
    kbts_run run;
    bool first = true;
    while (kbts_ShapeRun(g_ctx, &run)) {
        if (first) {
            out.rtl = run.ParagraphDirection == KBTS_DIRECTION_RTL;
            first = false;
        }
        shaped_layout::Run layout_run;
        layout_run.rtl = run.Direction == KBTS_DIRECTION_RTL;
        std::vector<ShapedGlyphInfo> infos;
        int font_index = FontIndexFor(run.Font);
        kbts_glyph* glyph = nullptr;
        while (kbts_GlyphIteratorNext(&run.Glyphs, &glyph)) {
            shaped_layout::Glyph lg;
            ShapedGlyphInfo info;
            info.font = font_index;
            info.id = glyph->Id;
            if (font_index >= 0) {
                const Font& font = g_fonts[font_index];
                float scale = 0.0f;
                if (font.is_emoji) {
                    scale = pixel_height /
                            static_cast<float>(font.hhea_asc - font.hhea_desc);
                } else if (font.stb_ok) {
                    scale = stbtt_ScaleForPixelHeight(&font.stb, pixel_height);
                }
                lg.advance = static_cast<float>(glyph->AdvanceX) * scale;
                info.off_x = static_cast<float>(glyph->OffsetX) * scale;
                info.off_y = static_cast<float>(glyph->OffsetY) * scale;
            }
            uint32_t cp = glyph->Codepoint;
            lg.break_after = cp == 0x20 || IsCjk(cp);
            lg.break_is_space = cp == 0x20;
            layout_run.glyphs.push_back(lg);
            infos.push_back(info);
        }
        out.runs.push_back(layout_run);
        out.infos.push_back(infos);
    }
    return !out.runs.empty();
}

struct PlacedBitmap {
    int x = 0, y = 0, w = 0, h = 0;
    unsigned char* gray = nullptr;  // stb bitmap, freed after upload
    bool color = false;
    std::vector<unsigned char> rgba;  // downscaled RGBA for color glyphs
};

// Bakes one display-ordered glyph sequence into a tightly cropped
// texture. display holds (run, glyph) pairs in draw order.
CachedLine BakeLine(const ShapedParagraph& para,
                    const std::vector<std::pair<int, int>>& display,
                    float pixel_height) {
    CachedLine out;
    std::vector<PlacedBitmap> placed;
    float pen = 0.0f;
    int tex_height = static_cast<int>(pixel_height * 3.0f);
    int baseline = static_cast<int>(pixel_height * 1.4f);
    for (const auto& pos : display) {
        const ShapedGlyphInfo& info = para.infos[pos.first][pos.second];
        if (info.font < 0) continue;
        const Font& font = g_fonts[info.font];
        // Advance from the layout glyph (same scale as shaping).
        const shaped_layout::Glyph& lg = para.runs[pos.first].glyphs[pos.second];
        if (font.is_emoji) {
            FT_Error err = FT_Load_Glyph(font.ft_face, static_cast<FT_UInt>(info.id),
                                         FT_LOAD_COLOR | FT_LOAD_RENDER);
            if (err != 0) {
                pen += lg.advance;
                continue;
            }
            FT_GlyphSlot slot = font.ft_face->glyph;
            FT_Bitmap& bm = slot->bitmap;
            if (bm.pixel_mode != FT_PIXEL_MODE_BGRA || bm.width == 0 || bm.rows == 0) {
                pen += lg.advance;
                continue;
            }
            int th = static_cast<int>(pixel_height);
            int tw = static_cast<int>(static_cast<float>(bm.width) * th /
                                          static_cast<float>(bm.rows) +
                                      0.5f);
            if (tw < 1) tw = 1;
            std::vector<unsigned char> px(static_cast<size_t>(tw) * th * 4, 0);
            float sx = static_cast<float>(bm.width) / tw;
            float sy = static_cast<float>(bm.rows) / th;
            for (int y = 0; y < th; ++y) {
                for (int x = 0; x < tw; ++x) {
                    int x0 = static_cast<int>(x * sx);
                    int x1 = static_cast<int>((x + 1) * sx + 0.5f);
                    if (x1 <= x0) x1 = x0 + 1;
                    int y0 = static_cast<int>(y * sy);
                    int y1 = static_cast<int>((y + 1) * sy + 0.5f);
                    if (y1 <= y0) y1 = y0 + 1;
                    long r = 0, g = 0, b = 0, a = 0;
                    int n = 0;
                    for (int yy = y0; yy < y1 && yy < static_cast<int>(bm.rows); ++yy) {
                        for (int xx = x0; xx < x1 && xx < static_cast<int>(bm.width); ++xx) {
                            unsigned char* s = bm.buffer +
                                               static_cast<size_t>(yy) * bm.pitch +
                                               static_cast<size_t>(xx) * 4;
                            b += s[0];
                            g += s[1];
                            r += s[2];
                            a += s[3];
                            ++n;
                        }
                    }
                    if (n > 0) {
                        size_t idx = (static_cast<size_t>(y) * tw + x) * 4;
                        px[idx + 0] = static_cast<unsigned char>(r / n);
                        px[idx + 1] = static_cast<unsigned char>(g / n);
                        px[idx + 2] = static_cast<unsigned char>(b / n);
                        px[idx + 3] = static_cast<unsigned char>(a / n);
                    }
                }
            }
            float s = static_cast<float>(th) / static_cast<float>(bm.rows);
            PlacedBitmap p;
            p.x = static_cast<int>(pen + slot->bitmap_left * s);
            p.y = baseline - static_cast<int>(slot->bitmap_top * s);
            p.w = tw;
            p.h = th;
            p.color = true;
            p.rgba = std::move(px);
            placed.push_back(std::move(p));
        } else if (font.stb_ok) {
            float scale = stbtt_ScaleForPixelHeight(&font.stb, pixel_height);
            int w = 0, h = 0, xoff = 0, yoff = 0;
            unsigned char* bmp = stbtt_GetGlyphBitmap(&font.stb, scale, scale, info.id,
                                                      &w, &h, &xoff, &yoff);
            PlacedBitmap p;
            // OpenType Y offsets are y-up; texture coords are y-down.
            p.x = static_cast<int>(pen + info.off_x) + xoff;
            p.y = baseline + yoff - static_cast<int>(info.off_y);
            p.w = w;
            p.h = h;
            p.gray = bmp;
            placed.push_back(std::move(p));
        }
        pen += lg.advance;
    }
    int tex_width = static_cast<int>(pen + 0.5f) + 16;
    if (tex_width < 16) tex_width = 16;
    // Tight vertical crop: the band actually covered by bitmaps.
    int band_top = tex_height, band_bottom = 0;
    for (const auto& p : placed) {
        if (p.w <= 0 || p.h <= 0) continue;
        if (p.y < band_top) band_top = p.y;
        if (p.y + p.h > band_bottom) band_bottom = p.y + p.h;
    }
    if (band_bottom <= band_top) {
        for (auto& p : placed) free(p.gray);
        return out;  // nothing visible (e.g. spaces only)
    }
    int band_height = band_bottom - band_top;
    std::vector<unsigned char> rgba(static_cast<size_t>(tex_width) * band_height * 4, 0);
    for (auto& p : placed) {
        if (p.color) {
            for (int y = 0; y < p.h; ++y) {
                for (int x = 0; x < p.w; ++x) {
                    int tx = p.x + x, ty = p.y - band_top + y;
                    if (tx < 0 || ty < 0 || tx >= tex_width || ty >= band_height) continue;
                    size_t sidx = (static_cast<size_t>(y) * p.w + x) * 4;
                    if (p.rgba[sidx + 3] == 0) continue;
                    size_t idx = (static_cast<size_t>(ty) * tex_width + tx) * 4;
                    rgba[idx + 0] = p.rgba[sidx + 0];
                    rgba[idx + 1] = p.rgba[sidx + 1];
                    rgba[idx + 2] = p.rgba[sidx + 2];
                    rgba[idx + 3] = p.rgba[sidx + 3];
                }
            }
            continue;
        }
        if (p.gray == nullptr) continue;
        for (int y = 0; y < p.h; ++y) {
            for (int x = 0; x < p.w; ++x) {
                int tx = p.x + x, ty = p.y - band_top + y;
                if (tx < 0 || ty < 0 || tx >= tex_width || ty >= band_height) continue;
                unsigned char a = p.gray[static_cast<size_t>(y) * p.w + x];
                size_t idx = (static_cast<size_t>(ty) * tex_width + tx) * 4;
                rgba[idx + 0] = 255;
                rgba[idx + 1] = 255;
                rgba[idx + 2] = 255;
                if (a > rgba[idx + 3]) rgba[idx + 3] = a;
            }
        }
        free(p.gray);
    }
    GLuint tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, tex_width, band_height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, rgba.data());
    out.id = tex;
    out.width = static_cast<float>(tex_width);
    out.height = static_cast<float>(band_height);
    return out;
}

std::vector<std::string> SplitHardLines(const std::string& text) {
    std::vector<std::string> lines;
    size_t start = 0;
    while (true) {
        size_t nl = text.find('\n', start);
        std::string part = text.substr(start, nl == std::string::npos
                                                  ? std::string::npos
                                                  : nl - start);
        if (!part.empty() && part.back() == '\r') part.pop_back();
        lines.push_back(part);
        if (nl == std::string::npos) break;
        start = nl + 1;
    }
    return lines;
}

}  // namespace

bool InitShapedText(std::string& error) {
    if (g_ok) return true;
    g_ctx = kbts_CreateShapeContext(0, 0);
    if (g_ctx == nullptr) {
        error = "shaped text: cannot create kb context";
        return false;
    }
    if (FT_Init_FreeType(&g_ft) != 0) {
        error = "shaped text: FreeType init failed";
        kbts_DestroyShapeContext(g_ctx);
        g_ctx = nullptr;
        return false;
    }
    // Emoji first (bottom of the stack) so shared codepoints
    // resolve to the script fonts pushed after it.
    LoadFont("Noto Color Emoji", true, false, error);
    if (!LoadFont("Noto Sans", false, true, error)) {
        ShutdownShapedText();
        return false;
    }
    std::string ignored;
    LoadFont("Noto Sans Arabic", false, false, ignored);
    LoadFont("Noto Sans Devanagari", false, false, ignored);
    LoadFont("Noto Sans CJK SC", false, false, ignored);
    g_ok = true;
    return true;
}

void ShutdownShapedText() {
    ClearCache();
    for (auto& font : g_fonts) {
        if (font.ft_face != nullptr) FT_Done_Face(font.ft_face);
        free(font.data);
    }
    g_fonts.clear();
    if (g_ft != nullptr) {
        FT_Done_FreeType(g_ft);
        g_ft = nullptr;
    }
    if (g_ctx != nullptr) {
        kbts_DestroyShapeContext(g_ctx);
        g_ctx = nullptr;
    }
    g_ok = false;
}

bool GetShapedLine(const std::string& text, float pixel_height,
                   ShapedLineTexture& out) {
    if (!g_ok || text.empty()) return false;
    std::string key = text + "\x1f" + std::to_string(pixel_height);
    auto it = g_line_cache.find(key);
    if (it != g_line_cache.end()) {
        out.id = it->second.id;
        out.width = it->second.width;
        out.height = it->second.height;
        return out.id != 0;
    }
    if (g_line_cache.size() > 256) ClearCache();
    ShapedParagraph para;
    if (!ShapeParagraph(text, pixel_height, para)) {
        g_line_cache[key] = CachedLine();
        return false;
    }
    auto logical = shaped_layout::LogicalOrder(para.runs);
    auto display = shaped_layout::DisplayOrder(
        para.runs, logical, {0, static_cast<int>(logical.size())}, para.rtl);
    CachedLine baked = BakeLine(para, display, pixel_height);
    g_line_cache[key] = baked;
    out.id = baked.id;
    out.width = baked.width;
    out.height = baked.height;
    return out.id != 0;
}

void DrawShapedText(const std::string& text, float pixel_height) {
    ShapedLineTexture tex;
    if (GetShapedLine(text, pixel_height, tex)) {
        ImGui::Image(static_cast<ImTextureID>(tex.id),
                     ImVec2(tex.width, tex.height));
    } else if (!g_ok) {
        ImGui::Text("%s", text.c_str());
    } else {
        ImGui::Dummy(ImVec2(0, ImGui::GetTextLineHeight()));
    }
}

void DrawShapedWrapped(const std::string& text, float pixel_height,
                       float wrap_width) {
    if (!g_ok) {
        ImGui::TextWrapped("%s", text.c_str());
        return;
    }
    std::string key = text + "\x1f" + std::to_string(pixel_height) + "\x1f" +
                      std::to_string(wrap_width);
    auto it = g_wrapped_cache.find(key);
    std::vector<CachedLine> lines;
    if (it != g_wrapped_cache.end()) {
        lines = it->second;
    } else {
        if (g_wrapped_cache.size() > 64) ClearCache();
        for (const std::string& part : SplitHardLines(text)) {
            if (part.empty()) {
                lines.push_back(CachedLine());  // blank line: height only
                continue;
            }
            ShapedParagraph para;
            if (!ShapeParagraph(part, pixel_height, para)) {
                lines.push_back(CachedLine());
                continue;
            }
            auto logical = shaped_layout::LogicalOrder(para.runs);
            std::vector<shaped_layout::Glyph> flat;
            for (const auto& p : logical) {
                flat.push_back(para.runs[p.first].glyphs[p.second]);
            }
            auto wrapped = shaped_layout::WrapLines(flat, wrap_width);
            for (const auto& range : wrapped) {
                auto display = shaped_layout::DisplayOrder(para.runs, logical, range,
                                                           para.rtl);
                lines.push_back(BakeLine(para, display, pixel_height));
            }
        }
        g_wrapped_cache[key] = lines;
    }
    float start_x = ImGui::GetCursorPosX();
    bool first = true;
    for (const CachedLine& line : lines) {
        if (!first) ImGui::SetCursorPosX(start_x);
        first = false;
        if (line.id != 0) {
            ImGui::Image(static_cast<ImTextureID>(line.id),
                         ImVec2(line.width, line.height));
        } else {
            ImGui::Dummy(ImVec2(0, ImGui::GetTextLineHeight()));
        }
    }
}
