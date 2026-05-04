const std = @import("std");
const assert = std.debug.assert;
const dvui = @import("dvui");
const Allocator = std.mem.Allocator;

const dependencygraph = @import("dependencygraph");

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 800.0, .h = 600.0 },
        .max_size = .{ .w = 800.0, .h = 600.0 },
        .title = "Dependency Graph",
    } },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

var arena_allocator: std.heap.ArenaAllocator = undefined;
var orig_content_scale: f32 = 1.0;

pub fn appInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;
    arena_allocator = .init(std.heap.page_allocator);

    // Parse the package lock file at the start .
    const io = dvui.App.main_init.?.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const allocator = arena_allocator.allocator();
    var package = try dependencygraph.Package.init(io, allocator, "package-lock.json");
    defer package.deinit();

    if (package.packages.get("root")) |root| {
        if (root.dependencies) |dependencies| {
            var dep_it = dependencies.iterator();
            while (dep_it.next()) |pkg| {
                const name = pkg.key_ptr.*;
                const c_str = try allocator.dupeZ(u8, name);
                defer allocator.free(c_str);
            }
        }
    }

    try stdout.print("Dependencies count for {s}: {d}\n", .{ package.name, package.packages.count() });
    try stdout.flush(); // Don't forget to flush!
}

pub fn appDeinit() void {
    arena_allocator.deinit();
}

pub fn appFrame() !dvui.App.Result {
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    defer tl.deinit();
    tl.addText("Hello world!", .{});
    return .ok;
}
