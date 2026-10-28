const std = @import("std");

// Image files on disk, mirroring rust-egui/src/images.rs.
//
// A recipe's image_path is a path to a file, usually a copy
// inside the images/ directory next to recipes.db. Importing
// copies the chosen file there, so the recipe keeps working
// if the original file is later moved or deleted. It never
// overwrites an existing file: a second import of the same
// filename gets a _1, _2 suffix.
//
// DVUI has no native file picker, so unlike the Rust version
// (which uses rfd's file dialog), this version takes the
// source path from a text field in the edit form and copies
// it on Import. The returned path is allocated from an
// app-lifetime arena and is never freed.
//
// Zig 0.17 note: std.fs is gone in 0.17 (replaced by
// std.Io), so file work here goes through std.Io.Dir with a
// process-lifetime Threaded Io, and the basename/stem/
// extension helpers below are written by hand instead of
// using the deprecated std.fs.path.

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

/// Copy source_path into images/ (creating it if needed) and
/// return the stored path. If the source is already the stored
/// copy, it is returned unchanged. On a name collision the
/// copy gets a _1, _2 suffix before the extension.
pub fn importImage(source_path: []const u8) ![]const u8 {
    const io = getIo();
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "images");
    const filename = basename(source_path);
    if (filename.len == 0) return error.InvalidPath;
    const dest = try std.fmt.allocPrint(alloc, "images/{s}", .{filename});
    if (std.mem.eql(u8, dest, source_path)) return dest;
    if (try copyFile(io, cwd, source_path, dest)) return dest;
    const stem_part = stem(filename);
    const ext = extension(filename);
    var counter: u32 = 1;
    while (true) : (counter += 1) {
        const candidate = try std.fmt.allocPrint(alloc, "images/{s}_{d}{s}", .{ stem_part, counter, ext });
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
