// Unit tests for shaped_layout.h: line breaking and display order.
// Plain asserts, no test framework, matching the other cpp-imgui tests.

#include <cassert>
#include <cstdio>
#include <utility>
#include <vector>

#include "shaped_layout.h"

using namespace shaped_layout;

static int failures = 0;

#define CHECK(cond)                                                    \
    do {                                                               \
        if (!(cond)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);     \
            ++failures;                                                \
        }                                                              \
    } while (0)

static Glyph G(float adv, bool brk = false, bool space = false) {
    Glyph g;
    g.advance = adv;
    g.break_after = brk;
    g.break_is_space = space;
    return g;
}

// Logical stream "a b c": advances 10 each, spaces breakable.
// Greedy: "a b" (25) fits in 26, so line 1 is a-space-b and the
// second space is dropped; line 2 is "c".
static void test_wrap_spaces() {
    std::vector<Glyph> glyphs = {G(10), G(5, true, true), G(10), G(5, true, true), G(10)};
    auto lines = WrapLines(glyphs, 26.0f);
    CHECK(lines.size() == 2);
    CHECK(lines[0].first == 0 && lines[0].second == 3);
    CHECK(lines[1].first == 4 && lines[1].second == 5);
}

// Every glyph breakable (CJK-style): breaks at the width boundary,
// nothing dropped.
static void test_wrap_cjk() {
    std::vector<Glyph> glyphs = {G(10, true), G(10, true), G(10, true), G(10, true)};
    auto lines = WrapLines(glyphs, 25.0f);
    CHECK(lines.size() == 2);
    CHECK(lines[0].first == 0 && lines[0].second == 2);
    CHECK(lines[1].first == 2 && lines[1].second == 4);
}

// No break opportunity: hard break mid-word.
static void test_wrap_hard_break() {
    std::vector<Glyph> glyphs = {G(10), G(10), G(10)};
    auto lines = WrapLines(glyphs, 25.0f);
    CHECK(lines.size() == 2);
    CHECK(lines[0].first == 0 && lines[0].second == 2);
    CHECK(lines[1].first == 2 && lines[1].second == 3);
}

static void test_wrap_empty_and_nowrap() {
    CHECK(WrapLines({}, 100.0f).empty());
    std::vector<Glyph> glyphs = {G(10), G(10)};
    auto lines = WrapLines(glyphs, 0.0f);
    CHECK(lines.size() == 1);
    CHECK(lines[0].first == 0 && lines[0].second == 2);
}

// RTL paragraph "W1 W2": runs in logical order, glyphs in shaped
// order within each run. Display order of the whole line must be
// W2 (shaped), space, W1 (shaped).
static void test_display_rtl_single_line() {
    Run w1, sp, w2;
    w1.rtl = true;
    w1.glyphs = {G(10), G(10)};  // shaped order: last logical glyph first
    sp.rtl = true;
    sp.glyphs = {G(5)};
    w2.rtl = true;
    w2.glyphs = {G(10), G(10)};
    std::vector<Run> runs = {w1, sp, w2};
    auto logical = LogicalOrder(runs);
    // Logical order: w1 reversed, space, w2 reversed.
    CHECK(logical.size() == 5);
    CHECK(logical[0] == std::make_pair(0, 1));
    CHECK(logical[1] == std::make_pair(0, 0));
    CHECK(logical[2] == std::make_pair(1, 0));
    CHECK(logical[3] == std::make_pair(2, 1));
    CHECK(logical[4] == std::make_pair(2, 0));
    auto display = DisplayOrder(runs, logical, {0, 5}, true);
    CHECK(display.size() == 5);
    CHECK(display[0] == std::make_pair(2, 0));
    CHECK(display[1] == std::make_pair(2, 1));
    CHECK(display[2] == std::make_pair(1, 0));
    CHECK(display[3] == std::make_pair(0, 0));
    CHECK(display[4] == std::make_pair(0, 1));
}

// RTL paragraph wrapped to two lines: line 1 holds the first two
// logical words, displayed reversed; line 2 holds the last two.
static void test_display_rtl_wrapped() {
    Run w1, s1, w2, s2, w3, s3, w4;
    for (Run* r : {&w1, &s1, &w2, &s2, &w3, &s3, &w4}) r->rtl = true;
    w1.glyphs = {G(10)};
    s1.glyphs = {G(5, true, true)};
    w2.glyphs = {G(10)};
    s2.glyphs = {G(5, true, true)};
    w3.glyphs = {G(10)};
    s3.glyphs = {G(5, true, true)};
    w4.glyphs = {G(10)};
    std::vector<Run> runs = {w1, s1, w2, s2, w3, s3, w4};
    auto logical = LogicalOrder(runs);
    std::vector<Glyph> flat;
    for (const auto& p : logical) flat.push_back(runs[p.first].glyphs[p.second]);
    auto lines = WrapLines(flat, 26.0f);
    CHECK(lines.size() == 2);
    // Line 1: logical w1, space, w2 (the second space is dropped).
    CHECK(lines[0].first == 0 && lines[0].second == 3);
    // Line 2: logical w3, space, w4.
    CHECK(lines[1].first == 4 && lines[1].second == 7);
    auto d1 = DisplayOrder(runs, logical, lines[0], true);
    CHECK(d1.size() == 3);
    CHECK(d1[0] == std::make_pair(2, 0));
    CHECK(d1[1] == std::make_pair(1, 0));
    CHECK(d1[2] == std::make_pair(0, 0));
    auto d2 = DisplayOrder(runs, logical, lines[1], true);
    CHECK(d2.size() == 3);
    CHECK(d2[0] == std::make_pair(6, 0));
    CHECK(d2[1] == std::make_pair(5, 0));
    CHECK(d2[2] == std::make_pair(4, 0));
}

// LTR paragraph with an RTL insert: runs stay in logical order,
// glyphs inside the RTL run stay in shaped order.
static void test_display_ltr_with_rtl_insert() {
    Run latin, sp, arabic;
    latin.rtl = false;
    latin.glyphs = {G(10), G(10)};
    sp.rtl = false;
    sp.glyphs = {G(5)};
    arabic.rtl = true;
    arabic.glyphs = {G(10), G(10)};  // shaped order
    std::vector<Run> runs = {latin, sp, arabic};
    auto logical = LogicalOrder(runs);
    auto display = DisplayOrder(runs, logical, {0, 5}, false);
    CHECK(display.size() == 5);
    CHECK(display[0] == std::make_pair(0, 0));
    CHECK(display[1] == std::make_pair(0, 1));
    CHECK(display[2] == std::make_pair(1, 0));
    CHECK(display[3] == std::make_pair(2, 0));
    CHECK(display[4] == std::make_pair(2, 1));
}

int main() {
    test_wrap_spaces();
    test_wrap_cjk();
    test_wrap_hard_break();
    test_wrap_empty_and_nowrap();
    test_display_rtl_single_line();
    test_display_rtl_wrapped();
    test_display_ltr_with_rtl_insert();
    if (failures == 0) {
        printf("shaped layout tests: all passed\n");
        return 0;
    }
    printf("shaped layout tests: %d failures\n", failures);
    return 1;
}
