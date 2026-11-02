const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    // ICU bindings for text-encoding import (json_import.zig):
    // Zig 0.17 has no @cImport, so the ICU C headers are
    // translated at build time from src/icu.h. The translated
    // module is imported as "icu" by every root module whose
    // file graph reaches json_import.zig (the app, the
    // json_import tests, and the json_export tests, whose
    // round-trips re-import). The translated module links
    // libc; the ICU libraries themselves (Debian names
    // icuuc/icui18n) link per consuming module, exactly
    // like sqlite3 below.
    const icu_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/icu.h"),
        .target = target,
        .optimize = optimize,
    });
    const icu_mod = icu_translate.createModule();

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "glib", .module = gobject.module("glib2") },
            .{ .name = "gobject", .module = gobject.module("gobject2") },
            .{ .name = "gio", .module = gobject.module("gio2") },
            .{ .name = "gtk", .module = gobject.module("gtk4") },
            .{ .name = "gdk", .module = gobject.module("gdk4") },
            .{ .name = "gdkpixbuf", .module = gobject.module("gdkpixbuf2") },
            .{ .name = "icu", .module = icu_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zig-gobject",
        .root_module = mod,
        .use_llvm = true,
    });
    // db.zig declares the system SQLite C API by hand and
    // links the system library (see db.zig's header comment).
    exe.root_module.linkSystemLibrary("sqlite3", .{});
    exe.root_module.linkSystemLibrary("icuuc", .{});
    exe.root_module.linkSystemLibrary("icui18n", .{});
    b.installArtifact(exe);

    // Unit tests: title search (search.zig), seed counts
    // (recipes.zig), recipe data (db.zig), image file
    // copies (image_files.zig), network JSON import
    // (json_import.zig: parsing, URL handling, chunked
    // bodies, fetching from a local one-shot server, and
    // text-encoding import: BOM sniffing, ICU detection
    // and strict conversion, the shared encoding fixtures,
    // and encoded bodies over HTTP), and JSON export
    // (json_export.zig: single/collection serialization,
    // re-import round-trips, file-name sanitizing, and
    // file writes) — no UI or end-to-end tests. The
    // json_import and json_export tests link the system
    // SQLite library like the app does (json_import and
    // json_export import db.zig for its Recipe type, and
    // json_export imports json_import for its re-import
    // round-trip tests).
    const test_step = b.step("test", "Run unit tests");
    const test_roots = [_]struct { file: []const u8, sqlite: bool, icu: bool }{
        .{ .file = "src/search.zig", .sqlite = false, .icu = false },
        .{ .file = "src/recipes.zig", .sqlite = true, .icu = false },
        .{ .file = "src/db.zig", .sqlite = true, .icu = false },
        .{ .file = "src/image_files.zig", .sqlite = false, .icu = false },
        .{ .file = "src/json_import.zig", .sqlite = true, .icu = true },
        .{ .file = "src/json_export.zig", .sqlite = true, .icu = true },
    };
    for (test_roots) |root| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(root.file),
            .target = target,
            .optimize = optimize,
        });
        if (root.sqlite) test_mod.linkSystemLibrary("sqlite3", .{});
        if (root.icu) {
            test_mod.addImport("icu", icu_mod);
            test_mod.linkSystemLibrary("icuuc", .{});
            test_mod.linkSystemLibrary("icui18n", .{});
        }
        const tests = b.addTest(.{ .root_module = test_mod });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}
