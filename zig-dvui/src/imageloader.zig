const std = @import("std");
const dvui = @import("dvui");

// Asynchronous image loading, mirroring the Rust version's
// poll_image_loads: decoding happens on a worker thread, so
// a large image never blocks the UI, and the texture is only
// touched on the main thread.
//
// How it works, per image path:
//   - ensureStarted(path) spawns one worker thread (once;
//     cached, failed, and already-loading paths are never
//     re-spawned). The worker reads the file and decodes it
//     with stb_image — the same decoder DVUI itself uses for
//     image files (dvui.c.stbi_load_from_memory) — into RGBA
//     bytes, then reports back through a mutex-guarded slot.
//   - poll() runs on the main thread every frame and moves
//     finished decodes into the ready cache (pixels copied
//     into the app-lifetime arena, worker buffers freed) or
//     remembers the path as failed. Failures are never
//     retried.
//   - status(path) tells the UI what to draw: loading (a
//     spinner), ready (the pixels, via dvui.image's .pixels
//     source), or failed (the error label).
//
// Thread-safety notes: the worker allocates only from the
// page allocator, never from the shared arena (arena
// allocators are not thread-safe), and touches the shared
// slot only under its mutex. stb_image's own loads are
// reentrant; the only shared stb state is its failure-reason
// string, which is only ever read on failure paths here.
//
// Zig 0.17 note: std.fs is gone in 0.17 (replaced by
// std.Io), so the worker reads its file through a shared
// Threaded Io, created on first use from the main thread
// (ensureStarted runs on the main thread) and passed to the
// worker as an argument.

pub const LoadedImage = struct {
    rgba: []const u8,
    width: u32,
    height: u32,
};

pub const Status = enum { not_started, loading, ready, failed };

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const alloc = arena.allocator();

const Pending = struct {
    mutex: std.Io.Mutex = .init,
    done: bool = false,
    failed: bool = false,
    rgba: []u8 = &.{},
    width: u32 = 0,
    height: u32 = 0,
};

var ready_cache = std.StringHashMap(LoadedImage).init(alloc);
var failed_set = std.StringHashMap(void).init(alloc);
var pending_map = std.StringHashMap(*Pending).init(alloc);

// One Threaded Io for the app's lifetime; created on first
// use, always from the main thread, never deinitialized.
var io_threaded: ?std.Io.Threaded = null;

fn getIo() std.Io {
    if (io_threaded == null) {
        io_threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    }
    return io_threaded.?.io();
}

fn decodeWorker(path: []const u8, slot: *Pending, io: std.Io) void {
    // Read and decode on this thread only; both buffers use
    // the page allocator so nothing shared is touched.
    const page = std.heap.page_allocator;
    const file_bytes = std.Io.Dir.cwd().readFileAlloc(io, path, page, .limited(1 << 30)) catch {
        slot.mutex.lockUncancelable(io);
        slot.failed = true;
        slot.done = true;
        slot.mutex.unlock(io);
        return;
    };
    defer page.free(file_bytes);
    if (file_bytes.len == 0) {
        slot.mutex.lockUncancelable(io);
        slot.failed = true;
        slot.done = true;
        slot.mutex.unlock(io);
        return;
    }
    var w: c_int = undefined;
    var h: c_int = undefined;
    var channels: c_int = undefined;
    const data = dvui.c.stbi_load_from_memory(
        file_bytes.ptr,
        @intCast(file_bytes.len),
        &w,
        &h,
        &channels,
        4,
    );
    slot.mutex.lockUncancelable(io);
    defer slot.mutex.unlock(io);
    if (data == null or w <= 0 or h <= 0) {
        slot.failed = true;
        slot.done = true;
        return;
    }
    defer dvui.c.stbi_image_free(data);
    const size: usize = @intCast(w * h * 4);
    const pixels = page.alloc(u8, size) catch {
        slot.failed = true;
        slot.done = true;
        return;
    };
    @memcpy(pixels, data[0..size]);
    slot.rgba = pixels;
    slot.width = @intCast(w);
    slot.height = @intCast(h);
    slot.done = true;
}

/// Start loading path, unless it is already cached, failed,
/// or loading. Safe to call every frame; it spawns at most
/// one worker thread per path.
pub fn ensureStarted(path: []const u8) void {
    if (path.len == 0) return;
    if (ready_cache.contains(path)) return;
    if (failed_set.contains(path)) return;
    if (pending_map.contains(path)) return;
    const slot = alloc.create(Pending) catch return;
    slot.* = .{};
    pending_map.put(path, slot) catch return;
    const path_copy = alloc.dupe(u8, path) catch return;
    const thread = std.Thread.spawn(.{}, decodeWorker, .{ path_copy, slot, getIo() }) catch {
        // If no thread could be started, fail fast rather
        // than spin: the UI shows the error label.
        _ = pending_map.remove(path);
        failed_set.put(path, {}) catch {};
        return;
    };
    thread.detach();
}

/// Move finished decodes into the ready/failed sets. Call on
/// the main thread, once per frame, before drawing images.
pub fn poll() void {
    const io = getIo();
    // Collect finished paths first: removing map entries
    // while iterating the map would invalidate the iterator.
    // Zig 0.17 ArrayList is unmanaged: .empty plus append(alloc, …).
    var finished: std.ArrayList([]const u8) = .empty;
    defer finished.deinit(alloc);
    var it = pending_map.iterator();
    while (it.next()) |entry| {
        const slot = entry.value_ptr.*;
        slot.mutex.lockUncancelable(io);
        const done = slot.done;
        slot.mutex.unlock(io);
        if (done) finished.append(alloc, entry.key_ptr.*) catch continue;
    }
    for (finished.items) |path| {
        const slot = pending_map.get(path) orelse continue;
        slot.mutex.lockUncancelable(io);
        const failed = slot.failed;
        const rgba = slot.rgba;
        const width = slot.width;
        const height = slot.height;
        slot.mutex.unlock(io);
        // Copy worker-owned pixels into the arena (stable
        // pointer for DVUI's .pixels texture cache) and free
        // the worker buffers.
        if (!failed and rgba.len > 0) {
            const kept = alloc.dupe(u8, rgba) catch &.{};
            if (kept.len > 0) {
                ready_cache.put(path, .{ .rgba = kept, .width = width, .height = height }) catch {};
            } else {
                failed_set.put(path, {}) catch {};
            }
            std.heap.page_allocator.free(rgba);
        } else {
            failed_set.put(path, {}) catch {};
        }
        _ = pending_map.remove(path);
    }
}

pub fn status(path: []const u8) Status {
    if (ready_cache.contains(path)) return .ready;
    if (failed_set.contains(path)) return .failed;
    if (pending_map.contains(path)) return .loading;
    return .not_started;
}

/// The decoded pixels for a ready path, or null.
pub fn getReady(path: []const u8) ?LoadedImage {
    return ready_cache.get(path);
}
