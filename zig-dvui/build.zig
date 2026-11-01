const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl2,
    });
    const exe = b.addExecutable(.{
        .name = "zig-dvui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dvui", .module = dvui_dep.module("dvui_sdl2") },
            },
        }),
    });
    // db.zig uses the system SQLite C API, so the build needs
    // the system SQLite development package (libsqlite3-dev on
    // Ubuntu, sqlite-devel on Fedora); see db.zig. In Zig
    // 0.17, system libraries link through the root module,
    // not the executable step, and this also links libc.
    exe.root_module.linkSystemLibrary("sqlite3", .{});
    b.installArtifact(exe);

    // ICU bindings for text-encoding import (json_import.zig):
    // Zig 0.17 has no @cImport, so the ICU C headers are
    // translated at build time from src/icu.h. The translated
    // module is private to this package and imported as
    // "icu" by every root module whose file graph reaches
    // json_import.zig (the app, the json_import tests, and
    // the json_export tests, whose round-trips re-import).
    // The translated module links libc; the ICU libraries
    // themselves (Debian names icuuc/icui18n, from the
    // icu-uc/icu-i18n pkg-config modules) link below, per
    // consuming module, exactly like sqlite3 above.
    const icu_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/icu.h"),
        .target = target,
        .optimize = optimize,
    });
    const icu_mod = icu_translate.createModule();
    exe.root_module.addImport("icu", icu_mod);
    exe.root_module.linkSystemLibrary("icuuc", .{});
    exe.root_module.linkSystemLibrary("icui18n", .{});

    // Unit tests: recipe data (db.zig), search
    // (search.zig), network JSON import
    // (json_import.zig: parsing, URL handling, chunked
    // bodies, fetching from a local one-shot server,
    // inserting into a throwaway database, and
    // text-encoding import: BOM sniffing, ICU detection
    // and strict conversion, the shared encoding fixtures,
    // and encoded bodies over HTTP), and JSON
    // export (json_export.zig: single/collection
    // serialization, re-import round-trips, file-name
    // sanitizing, and file writes) — no UI or
    // end-to-end tests. No test module imports DVUI; the
    // db, json_import, and json_export tests link the
    // system SQLite library like the app does
    // (json_import and json_export import db.zig for its
    // Recipe type, and json_export imports json_import
    // for its re-import round-trip tests).
    const search_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/search.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_search_tests = b.addRunArtifact(search_tests);

    const db_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/db.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    db_tests.root_module.linkSystemLibrary("sqlite3", .{});
    const run_db_tests = b.addRunArtifact(db_tests);

    const json_import_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/json_import.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    json_import_tests.root_module.linkSystemLibrary("sqlite3", .{});
    json_import_tests.root_module.addImport("icu", icu_mod);
    json_import_tests.root_module.linkSystemLibrary("icuuc", .{});
    json_import_tests.root_module.linkSystemLibrary("icui18n", .{});
    const run_json_import_tests = b.addRunArtifact(json_import_tests);

    const json_export_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/json_export.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    json_export_tests.root_module.linkSystemLibrary("sqlite3", .{});
    json_export_tests.root_module.addImport("icu", icu_mod);
    json_export_tests.root_module.linkSystemLibrary("icuuc", .{});
    json_export_tests.root_module.linkSystemLibrary("icui18n", .{});
    const run_json_export_tests = b.addRunArtifact(json_export_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_search_tests.step);
    test_step.dependOn(&run_db_tests.step);
    test_step.dependOn(&run_json_import_tests.step);
    test_step.dependOn(&run_json_export_tests.step);
}
