const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "glib", .module = gobject.module("glib2") },
            .{ .name = "gobject", .module = gobject.module("gobject2") },
            .{ .name = "gio", .module = gobject.module("gio2") },
            .{ .name = "gtk", .module = gobject.module("gtk4") },
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
    b.installArtifact(exe);
}
