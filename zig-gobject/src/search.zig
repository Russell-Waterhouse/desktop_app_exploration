// Title search for the recipe list, mirroring
// cpp-gtk4's search.h: case-insensitive substring match
// on the recipe TITLE only; an empty query matches
// everything; the query is NOT trimmed. (ASCII
// case-folding only, like cpp-gtk4's: probe titles in
// other scripts match by their exact bytes.)
//
// Split out of main.zig so the filter is unit-testable
// without a GTK display.

const std = @import("std");

pub fn titleMatchesSearch(title: [:0]const u8, query: [:0]const u8) bool {
    if (query.len == 0) return true;
    if (query.len > title.len) return false;
    var i: usize = 0;
    while (i + query.len <= title.len) : (i += 1) {
        var ok = true;
        for (query, 0..) |qc, j| {
            if (std.ascii.toLower(title[i + j]) != std.ascii.toLower(qc)) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

test "search matches case-insensitive substring" {
    try std.testing.expect(titleMatchesSearch("Tomato Basil Pasta", "PASTA"));
    try std.testing.expect(titleMatchesSearch("Tomato Basil Pasta", "pasta"));
    try std.testing.expect(titleMatchesSearch("Tomato Basil Pasta", "tomato"));
    try std.testing.expect(titleMatchesSearch("Banana Bread", "a"));
    try std.testing.expect(!titleMatchesSearch("Chicken Stir Fry", "a"));
}

test "search empty query matches all, longer query matches none" {
    try std.testing.expect(titleMatchesSearch("Banana Bread", ""));
    try std.testing.expect(!titleMatchesSearch("Banana Bread", "Banana Bread!"));
    try std.testing.expect(!titleMatchesSearch("Banana Bread", "xyz"));
}

test "search query is not trimmed" {
    try std.testing.expect(!titleMatchesSearch("Banana Bread", " Banana"));
    try std.testing.expect(!titleMatchesSearch("Banana Bread", "Bread "));
}
