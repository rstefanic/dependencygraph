const std = @import("std");
const assert = std.debug.assert;
const dvui = @import("dvui");
const App = @import("App.zig");
const Allocator = std.mem.Allocator;

const dependencygraph = @import("dependencygraph");
const Search = @import("search.zig");

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 800.0, .h = 600.0 },
            .title = "Dependency Graph",
        },
    },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};

var app: App = .{ .selection_active = "root" };
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

var arena_allocator: std.heap.ArenaAllocator = undefined;
var orig_content_scale: f32 = 1.0;

pub fn appInit(win: *dvui.Window) !void {
    const io = dvui.App.main_init.?.io;
    orig_content_scale = win.content_scale;
    arena_allocator = .init(std.heap.page_allocator);
    const allocator = arena_allocator.allocator();
    app.lockfile = try dependencygraph.LockFile.init(io, allocator, "package-lock.json");
    app.arena_allocator = arena_allocator;
    try app.selection_history.append(allocator, "root");
}

pub fn appDeinit() void {
    app.lockfile.deinit();
    arena_allocator.deinit();
}

pub fn appFrame() !dvui.App.Result {
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
    defer scroll.deinit();

    const padding_box = dvui.box(@src(), .{}, .{ .expand = .both, .id_extra = 0x0123456789, .margin = dvui.Rect{ .x = 20, .y = 10, .w = 20, .h = 10 } });
    defer padding_box.deinit();

    // Render the search model if the user has opened it.
    try Search.frame(&app);

    {
        const header_box = dvui.flexbox(@src(), .{}, .{ .expand = .horizontal });
        defer header_box.deinit();
        const selected_package_name = if (std.mem.eql(u8, app.selection_active, "root")) app.lockfile.name else app.selection_active;
        dvui.label(@src(), "{s}", .{selected_package_name}, .{ .expand = .horizontal, .font = .theme(.title) });
    }
    {
        // TODO: Either move this or rename this label once I have a better idea. This is misleading.
        const header_box = dvui.flexbox(@src(), .{}, .{ .expand = .horizontal });
        defer header_box.deinit();
        dvui.label(@src(), "Dependency count: {d}", .{app.lockfile.packages.count()}, .{ .expand = .horizontal });
    }

    {
        const nav_box = dvui.flexbox(@src(), .{ .justify_content = .start }, .{ .expand = .horizontal });
        defer nav_box.deinit();

        // Back button if there's history
        const button_enabled = app.selection_history.items.len > 1;
        if (button_enabled) {
            const clicked = dvui.button(@src(), "Back", .{}, .{});
            if (clicked) {
                _ = app.selection_history.pop(); // Remove last element
                app.selection_active = app.selection_history.items[app.selection_history.items.len - 1];
            }
        }
    }

    if (app.lockfile.packages.get(app.selection_active)) |pkg| {
        return app.packageTrees(pkg);
    } else {
        dvui.label(@src(), "Could not find package \"{s}\".", .{app.selection_active}, .{ .expand = .horizontal });
    }

    return .ok;
}
