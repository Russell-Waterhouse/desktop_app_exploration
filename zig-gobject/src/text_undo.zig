const std = @import("std");

// Per-field undo/redo for the add/edit form's text widgets.
//
// GTK4's GtkEntry and GtkTextView have no built-in undo, so
// the form keeps one TextUndo per text widget. This module
// knows nothing about GTK: the form records the widget's
// text after each change and applies the snapshot undo() or
// redo() returns.
//
// A snapshot holds the text plus the cursor as a CHARACTER
// offset, not a byte offset: that is what GtkEditable
// positions and GtkTextIter offsets count, so the GTK glue
// passes the values straight through for both widget kinds.
//
// Typing runs coalesce: changes less than coalesce_ns apart
// do not add a new undo step, so one Ctrl+Z undoes a run of
// typing instead of a single character. A change after an
// undo clears the redo stack, as usual. While the form is
// applying an undo/redo snapshot, it sets applying so the
// change signal that fires does not record the application
// as a new edit.
//
// Ownership: every string the struct holds is a dupe from
// its allocator, and undo()/redo() return a fresh dupe the
// caller owns (free it after applying). deinit frees
// everything the struct still holds.

/// Zig 0.17 has no Allocator.dupeZ.
fn dupeZ(alloc: std.mem.Allocator, s: []const u8) ![:0]const u8 {
    const buf = try alloc.alloc(u8, s.len + 1);
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf[0..s.len :0];
}

pub const Snapshot = struct {
    text: [:0]const u8,
    cursor: i32,
};

pub const TextUndo = struct {
    alloc: std.mem.Allocator,
    /// Nanoseconds since an arbitrary point (monotonic).
    /// Injected because Zig 0.17's std has no timestamp
    /// helper: the app passes glib monotonic time, tests
    /// pass a fake clock.
    now_ns: *const fn () i128,
    last: Snapshot,
    undo_stack: std.ArrayList(Snapshot),
    redo_stack: std.ArrayList(Snapshot),
    last_time_ns: i128,
    can_coalesce: bool,
    applying: bool,

    /// Longest gap between two changes that still counts as
    /// one typing run for undo purposes, in nanoseconds.
    pub const coalesce_ns: i128 = 1_000_000_000;

    pub fn init(
        alloc: std.mem.Allocator,
        now_ns: *const fn () i128,
        text: [:0]const u8,
        cursor: i32,
    ) TextUndo {
        return .{
            .alloc = alloc,
            .now_ns = now_ns,
            .last = .{ .text = dupeZ(alloc, text) catch @panic("oom"), .cursor = cursor },
            .undo_stack = .empty,
            .redo_stack = .empty,
            .last_time_ns = 0,
            .can_coalesce = false,
            .applying = false,
        };
    }

    pub fn deinit(self: *TextUndo) void {
        self.alloc.free(self.last.text);
        for (self.undo_stack.items) |snap| self.alloc.free(snap.text);
        for (self.redo_stack.items) |snap| self.alloc.free(snap.text);
        self.undo_stack.deinit(self.alloc);
        self.redo_stack.deinit(self.alloc);
        self.* = undefined;
    }

    fn freeStack(self: *TextUndo, stack: *std.ArrayList(Snapshot)) void {
        for (stack.items) |snap| self.alloc.free(snap.text);
        stack.clearRetainingCapacity();
    }

    /// The widget's initial contents. Clears both stacks.
    pub fn seed(self: *TextUndo, text: [:0]const u8, cursor: i32) void {
        self.freeStack(&self.undo_stack);
        self.freeStack(&self.redo_stack);
        self.alloc.free(self.last.text);
        self.last = .{ .text = dupeZ(self.alloc, text) catch @panic("oom"), .cursor = cursor };
        self.can_coalesce = false;
        self.applying = false;
    }

    /// Record the widget's text after a change. A record with
    /// unchanged text still refreshes the cursor.
    pub fn record(self: *TextUndo, text: [:0]const u8, cursor: i32) void {
        if (self.applying) return;
        if (std.mem.eql(u8, text, self.last.text)) {
            self.last.cursor = cursor;
            return;
        }
        const now = self.now_ns();
        const coalesce = self.can_coalesce and now - self.last_time_ns < coalesce_ns;
        if (!coalesce) {
            self.undo_stack.append(self.alloc, .{
                .text = dupeZ(self.alloc, self.last.text) catch @panic("oom"),
                .cursor = self.last.cursor,
            }) catch @panic("oom");
        }
        // When coalescing, the stack top already holds the
        // state from before the typing run; leave it alone.
        self.freeStack(&self.redo_stack);
        self.alloc.free(self.last.text);
        self.last = .{ .text = dupeZ(self.alloc, text) catch @panic("oom"), .cursor = cursor };
        self.last_time_ns = now;
        self.can_coalesce = true;
    }

    /// The snapshot to restore, or null when there is no
    /// step. Takes the widget's current contents so redo can
    /// return to them. Also refreshes the last-recorded
    /// state, so a later record is a new step rather than a
    /// continuation of the undone run.
    pub fn undo(self: *TextUndo, text: [:0]const u8, cursor: i32) ?Snapshot {
        if (self.undo_stack.items.len == 0) return null;
        self.redo_stack.append(self.alloc, .{
            .text = dupeZ(self.alloc, text) catch @panic("oom"),
            .cursor = cursor,
        }) catch @panic("oom");
        const popped = self.undo_stack.pop().?;
        self.alloc.free(self.last.text);
        self.last = popped;
        self.last_time_ns = self.now_ns();
        self.can_coalesce = false;
        return .{ .text = dupeZ(self.alloc, popped.text) catch @panic("oom"), .cursor = popped.cursor };
    }

    pub fn redo(self: *TextUndo, text: [:0]const u8, cursor: i32) ?Snapshot {
        if (self.redo_stack.items.len == 0) return null;
        self.undo_stack.append(self.alloc, .{
            .text = dupeZ(self.alloc, text) catch @panic("oom"),
            .cursor = cursor,
        }) catch @panic("oom");
        const popped = self.redo_stack.pop().?;
        self.alloc.free(self.last.text);
        self.last = popped;
        self.last_time_ns = self.now_ns();
        self.can_coalesce = false;
        return .{ .text = dupeZ(self.alloc, popped.text) catch @panic("oom"), .cursor = popped.cursor };
    }

    /// Set while the form applies a snapshot, so the
    /// resulting change signal is not recorded as a new edit.
    pub fn setApplying(self: *TextUndo, applying: bool) void {
        self.applying = applying;
    }

    pub fn canUndo(self: *TextUndo) bool {
        return self.undo_stack.items.len > 0;
    }

    pub fn canRedo(self: *TextUndo) bool {
        return self.redo_stack.items.len > 0;
    }
};

var fake_now: i128 = 0;

fn fakeClock() i128 {
    return fake_now;
}

test "typing run is one step" {
    fake_now = 0;
    var u = TextUndo.init(std.testing.allocator, &fakeClock, "", 0);
    defer u.deinit();
    u.record("H", 1);
    u.record("He", 2);
    u.record("Hel", 3);
    try std.testing.expect(u.canUndo());
    const snap = u.undo("Hel", 3) orelse return error.NoUndo;
    defer std.testing.allocator.free(snap.text);
    try std.testing.expectEqualStrings("", snap.text);
    try std.testing.expectEqual(@as(i32, 0), snap.cursor);
    try std.testing.expect(!u.canUndo());
    const back = u.redo("", 0) orelse return error.NoRedo;
    defer std.testing.allocator.free(back.text);
    try std.testing.expectEqualStrings("Hel", back.text);
    try std.testing.expectEqual(@as(i32, 3), back.cursor);
}

test "slow typing is separate steps" {
    fake_now = 0;
    var u = TextUndo.init(std.testing.allocator, &fakeClock, "", 0);
    defer u.deinit();
    u.record("H", 1);
    fake_now += TextUndo.coalesce_ns + 1;
    u.record("He", 2);
    const snap = u.undo("He", 2) orelse return error.NoUndo;
    defer std.testing.allocator.free(snap.text);
    try std.testing.expectEqualStrings("H", snap.text);
    try std.testing.expectEqual(@as(i32, 1), snap.cursor);
    const snap2 = u.undo("H", 1) orelse return error.NoUndo;
    defer std.testing.allocator.free(snap2.text);
    try std.testing.expectEqualStrings("", snap2.text);
    try std.testing.expectEqual(@as(i32, 0), snap2.cursor);
}

test "fresh has no steps" {
    fake_now = 0;
    var u = TextUndo.init(std.testing.allocator, &fakeClock, "abc", 3);
    defer u.deinit();
    try std.testing.expect(u.undo("abc", 3) == null);
    try std.testing.expect(u.redo("abc", 3) == null);
}

test "edit after undo clears redo" {
    fake_now = 0;
    var u = TextUndo.init(std.testing.allocator, &fakeClock, "", 0);
    defer u.deinit();
    u.record("a", 1);
    const snap = u.undo("a", 1) orelse return error.NoUndo;
    defer std.testing.allocator.free(snap.text);
    try std.testing.expect(u.canRedo());
    u.record("b", 1);
    try std.testing.expect(!u.canRedo());
    const snap2 = u.undo("b", 1) orelse return error.NoUndo;
    defer std.testing.allocator.free(snap2.text);
    try std.testing.expectEqualStrings("", snap2.text);
}

test "cursor restored with text" {
    fake_now = 0;
    var u = TextUndo.init(std.testing.allocator, &fakeClock, "hello", 5);
    defer u.deinit();
    u.record("hell", 4);
    const snap = u.undo("hell", 4) orelse return error.NoUndo;
    defer std.testing.allocator.free(snap.text);
    try std.testing.expectEqualStrings("hello", snap.text);
    try std.testing.expectEqual(@as(i32, 5), snap.cursor);
}

test "unchanged and applying add no step" {
    fake_now = 0;
    var u = TextUndo.init(std.testing.allocator, &fakeClock, "x", 1);
    defer u.deinit();
    u.record("x", 1);
    try std.testing.expect(!u.canUndo());
    u.setApplying(true);
    u.record("y", 1);
    u.setApplying(false);
    try std.testing.expect(!u.canUndo());
}

test "redo chains back" {
    fake_now = 0;
    var u = TextUndo.init(std.testing.allocator, &fakeClock, "", 0);
    defer u.deinit();
    u.record("a", 1);
    fake_now += TextUndo.coalesce_ns + 1;
    u.record("ab", 2);
    const undo1 = u.undo("ab", 2) orelse return error.NoUndo;
    defer std.testing.allocator.free(undo1.text);
    const undo2 = u.undo("a", 1) orelse return error.NoUndo;
    defer std.testing.allocator.free(undo2.text);
    const snap = u.redo("", 0) orelse return error.NoRedo;
    defer std.testing.allocator.free(snap.text);
    try std.testing.expectEqualStrings("a", snap.text);
    try std.testing.expectEqual(@as(i32, 1), snap.cursor);
    const snap2 = u.redo("a", 1) orelse return error.NoRedo;
    defer std.testing.allocator.free(snap2.text);
    try std.testing.expectEqualStrings("ab", snap2.text);
    try std.testing.expectEqual(@as(i32, 2), snap2.cursor);
    try std.testing.expect(!u.canRedo());
}
