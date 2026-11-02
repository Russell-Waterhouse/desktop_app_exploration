// Image files on disk, mirroring rust-egui/src/images.rs
// and odin-gtk/src/images.odin's copy_image_file.
//
// A recipe's image_path is a path to a file, usually a copy
// inside the images/ directory next to recipes.db. Importing
// copies the chosen file there, so the recipe keeps working
// if the original file is later moved or deleted. It never
// overwrites an existing file: a second import of the same
// filename gets a _1, _2 suffix before the extension.
//
// This module only copies files. Decoding and display live
// in main.zig (worker-thread GdkPixbuf decode, main-thread
// GtkPicture paintable), so this file needs no GTK import
// and its tests run without a display.
//
// Zig 0.17 note: std.fs is gone in 0.17 (replaced by
// std.Io), so file work here goes through std.Io.Dir with
// a process-lifetime Threaded Io, and the basename/stem/
// extension helpers below are written by hand.

const std = @import("std");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const alloc = arena.allocator();

// One Threaded Io for the app's lifetime; created on first
// use, always from the main thread (import runs on a UI
// button click), never deinitialized.
var io_threaded: ?std.Io.Threaded = null;

fn getIo() std.Io {
    if (io_threaded == null) {
        io_threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    }
    return io_threaded.?.io();
}

fn basename(path: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[idx + 1 ..];
}

fn extension(filename: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfScalar(u8, filename, '.') orelse return "";
    if (idx == 0) return "";
    return filename[idx..];
}

fn stem(filename: []const u8) []const u8 {
    const ext = extension(filename);
    return filename[0 .. filename.len - ext.len];
}

/// Copy source_path into dest_dir (creating it if needed)
/// and return the stored path, relative like dest_dir
/// ("images/<name>"). If the source is already the stored
/// copy, it is returned unchanged. On a name collision the
/// copy gets a _1, _2 suffix before the extension. A
/// missing source is an error, not a silent skip.
pub fn copyImageFile(source_path: []const u8, dest_dir: []const u8) ![]const u8 {
    const io = getIo();
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, dest_dir);
    const filename = basename(source_path);
    if (filename.len == 0) return error.InvalidPath;
    const dest = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dest_dir, filename });
    if (std.mem.eql(u8, dest, source_path)) return dest;
    if (try copyFile(io, cwd, source_path, dest)) return dest;
    const stem_part = stem(filename);
    const ext = extension(filename);
    var counter: u32 = 1;
    while (true) : (counter += 1) {
        const candidate = try std.fmt.allocPrint(alloc, "{s}/{s}_{d}{s}", .{ dest_dir, stem_part, counter, ext });
        if (try copyFile(io, cwd, source_path, candidate)) return candidate;
    }
}

/// Copy source to dest; returns false when dest already
/// exists (so the caller can try a suffixed name), and
/// propagates any other error (e.g. a missing source file).
fn copyFile(io: std.Io, cwd: std.Io.Dir, source: []const u8, dest: []const u8) !bool {
    cwd.copyFile(source, cwd, dest, io, .{ .replace = false }) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => return err,
    };
    return true;
}

// --- Tests ---

const test_alloc = std.testing.allocator;

test "copy image file copies and collides with suffix" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(std.testing.io, &dir_buf);
    const dir = dir_buf[0..n];
    const io = std.testing.io;
    // A source file inside the temp dir.
    const src = try std.fmt.allocPrint(test_alloc, "{s}/photo.png", .{dir});
    defer test_alloc.free(src);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = src, .data = "fake-png-bytes" });
    // Copy into an explicit dest dir under /tmp (the
    // module's copy uses the process cwd, so the dest
    // dir here is absolute, not "images").
    const dest_dir = try std.fmt.allocPrint(test_alloc, "{s}/pics", .{dir});
    defer test_alloc.free(dest_dir);
    const first = try copyImageFile(src, dest_dir);
    const want_first = try std.fmt.allocPrint(test_alloc, "{s}/photo.png", .{dest_dir});
    defer test_alloc.free(want_first);
    try std.testing.expectEqualStrings(want_first, first);
    const first_bytes = try std.Io.Dir.cwd().readFileAlloc(io, first, test_alloc, .limited(1 << 20));
    defer test_alloc.free(first_bytes);
    try std.testing.expectEqualStrings("fake-png-bytes", first_bytes);
    // A second copy of the same name gets _1.
    const second = try copyImageFile(src, dest_dir);
    const want_second = try std.fmt.allocPrint(test_alloc, "{s}/photo_1.png", .{dest_dir});
    defer test_alloc.free(want_second);
    try std.testing.expectEqualStrings(want_second, second);
    const second_bytes = try std.Io.Dir.cwd().readFileAlloc(io, second, test_alloc, .limited(1 << 20));
    defer test_alloc.free(second_bytes);
    try std.testing.expectEqualStrings("fake-png-bytes", second_bytes);
}

test "copy image file with missing source is an error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(std.testing.io, &dir_buf);
    const dir = dir_buf[0..n];
    const src = try std.fmt.allocPrint(test_alloc, "{s}/no-such.png", .{dir});
    defer test_alloc.free(src);
    const dest_dir = try std.fmt.allocPrint(test_alloc, "{s}/pics", .{dir});
    defer test_alloc.free(dest_dir);
    try std.testing.expectError(error.FileNotFound, copyImageFile(src, dest_dir));
}
