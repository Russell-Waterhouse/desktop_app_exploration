const std = @import("std");
const dvui = @import("dvui");

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 400.0, .h = 300.0 },
            .title = "Hello DVUI",
            .org = "example",
            .app = "hello-dvui",
        },
    },
    .frameFn = appFrame,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

pub fn appFrame() !dvui.App.Result {
    var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .background = true });
    defer box.deinit();
    dvui.label(@src(), "Hello, world!", .{}, .{});
    return .ok;
}
