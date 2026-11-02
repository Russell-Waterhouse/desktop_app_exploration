#pragma once

// Pure line-layout logic for shaped text: no font, shaping, or
// graphics dependency, so it is unit-testable on its own.
//
// The shaper (kb) returns runs in logical order, with the glyphs
// inside each run already in visual order (RTL runs are flipped).
// Line breaking must happen in logical order, and display order
// is reconstructed per line: runs in logical order for LTR
// paragraphs, reversed for RTL paragraphs, with glyphs inside
// each run in their shaped order.
//
// Shaping whole paragraphs and then splitting is exact for this
// corpus: joining (Arabic) and conjuncts (Devanagari) are
// word-internal, and breaks only happen at spaces or between
// CJK ideographs, never inside a word's shaping context.

#include <utility>
#include <vector>

namespace shaped_layout {

struct Glyph {
    float advance = 0.0f;      // advance in pixels at the render size
    bool break_after = false;  // a line may break after this glyph
    bool break_is_space = false;  // the break glyph is a space, dropped at breaks
};

struct Run {
    bool rtl = false;
    std::vector<Glyph> glyphs;  // in shaped (visual) order within the run
};

// Logical glyph order: (run index, glyph index) pairs, in logical
// order. RTL runs are reversed back to logical order; LTR runs
// are kept as shaped.
std::vector<std::pair<int, int>> LogicalOrder(const std::vector<Run>& runs);

// Greedy wrap of a logical glyph stream (advances in pixels).
// Returns [begin, end) ranges over the logical stream. A space
// used as a break point is dropped (excluded from both lines).
// When no break opportunity fits, the line is hard-broken at the
// overflowing glyph. A non-positive width means no wrapping.
std::vector<std::pair<int, int>> WrapLines(const std::vector<Glyph>& glyphs,
                                           float width);

// Display order for one line: (run, glyph) pairs in the order to
// draw, left to right. logical_line is a [begin, end) range over
// the logical stream; logical maps stream positions to
// (run, glyph). Runs are grouped in first-appearance order, then
// reversed as a group for RTL paragraphs; within a group, RTL
// runs are reversed back to shaped order and LTR runs are kept.
std::vector<std::pair<int, int>> DisplayOrder(
    const std::vector<Run>& runs,
    const std::vector<std::pair<int, int>>& logical,
    std::pair<int, int> logical_line, bool paragraph_rtl);

inline std::vector<std::pair<int, int>> LogicalOrder(const std::vector<Run>& runs) {
    std::vector<std::pair<int, int>> logical;
    for (int r = 0; r < static_cast<int>(runs.size()); ++r) {
        const Run& run = runs[r];
        if (run.rtl) {
            for (int g = static_cast<int>(run.glyphs.size()) - 1; g >= 0; --g) {
                logical.push_back({r, g});
            }
        } else {
            for (int g = 0; g < static_cast<int>(run.glyphs.size()); ++g) {
                logical.push_back({r, g});
            }
        }
    }
    return logical;
}

inline std::vector<std::pair<int, int>> WrapLines(const std::vector<Glyph>& glyphs,
                                                  float width) {
    std::vector<std::pair<int, int>> lines;
    if (glyphs.empty()) {
        return lines;
    }
    if (width <= 0.0f) {
        lines.push_back({0, static_cast<int>(glyphs.size())});
        return lines;
    }
    int start = 0;
    float line_width = 0.0f;
    int last_break = -1;  // index of last break opportunity in this line
    for (int i = 0; i < static_cast<int>(glyphs.size()); ++i) {
        if (i > start && line_width + glyphs[i].advance > width) {
            if (glyphs[i].break_after && glyphs[i].break_is_space) {
                // The overflowing glyph is itself a space: the line
                // ends before it, and the space is dropped.
                lines.push_back({start, i});
                start = i + 1;
                line_width = 0.0f;
                last_break = -1;
                continue;
            }
            if (last_break >= start) {
                if (glyphs[last_break].break_is_space) {
                    lines.push_back({start, last_break});
                } else {
                    lines.push_back({start, last_break + 1});
                }
                start = last_break + 1;
                // Recompute the current line's width and break
                // state for the glyphs already scanned past start.
                line_width = 0.0f;
                last_break = -1;
                for (int j = start; j < i; ++j) {
                    line_width += glyphs[j].advance;
                    if (glyphs[j].break_after) {
                        last_break = j;
                    }
                }
            } else {
                // No break opportunity: hard-break before this glyph.
                lines.push_back({start, i});
                start = i;
                line_width = 0.0f;
                last_break = -1;
            }
        }
        line_width += glyphs[i].advance;
        if (glyphs[i].break_after) {
            last_break = i;
        }
    }
    if (start < static_cast<int>(glyphs.size())) {
        lines.push_back({start, static_cast<int>(glyphs.size())});
    }
    return lines;
}

inline std::vector<std::pair<int, int>> DisplayOrder(
    const std::vector<Run>& runs,
    const std::vector<std::pair<int, int>>& logical,
    std::pair<int, int> logical_line, bool paragraph_rtl) {
    // Group the line's glyphs by run, in first-appearance order.
    std::vector<std::vector<std::pair<int, int>>> groups;
    std::vector<int> group_run;
    for (int p = logical_line.first; p < logical_line.second; ++p) {
        int r = logical[p].first;
        if (groups.empty() || group_run.back() != r) {
            groups.push_back({});
            group_run.push_back(r);
        }
        groups.back().push_back(logical[p]);
    }
    std::vector<std::pair<int, int>> display;
    // Iterate groups in logical order, or reversed for RTL.
    for (int gi = 0; gi < static_cast<int>(groups.size()); ++gi) {
        int idx = paragraph_rtl ? static_cast<int>(groups.size()) - 1 - gi : gi;
        const auto& group = groups[idx];
        int run_index = group_run[idx];
        if (runs[run_index].rtl) {
            // Logical order within an RTL run is the reverse of
            // shaped order; flip back to shaped order for display.
            for (int k = static_cast<int>(group.size()) - 1; k >= 0; --k) {
                display.push_back(group[k]);
            }
        } else {
            for (const auto& glyph : group) {
                display.push_back(glyph);
            }
        }
    }
    return display;
}

}  // namespace shaped_layout
