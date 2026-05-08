const std = @import("std");
const assert = std.debug.assert;
const dvui = @import("dvui");
const App = @import("App.zig");
const Allocator = std.mem.Allocator;

const dependencygraph = @import("dependencygraph");

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

var app: App = .{};
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
    app.package = try dependencygraph.Package.init(io, allocator, "package-lock.json");
}

pub fn appDeinit() void {
    app.package.deinit();
    arena_allocator.deinit();
}

pub fn appFrame() !dvui.App.Result {
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
    defer scroll.deinit();

    if (app.package.packages.get("root")) |root| {
        const padding_box = dvui.box(@src(), .{}, .{ .expand = .both, .id_extra = 0x0123456789, .margin = dvui.Rect{ .x = 20, .y = 10, .w = 20, .h = 10 } });
        defer padding_box.deinit();

        {
            const header_box = dvui.flexbox(@src(), .{}, .{ .expand = .horizontal });
            defer header_box.deinit();
            dvui.label(@src(), "{s}", .{app.package.name}, .{ .expand = .horizontal, .font = .theme(.title) });
        }
        {
            const header_box = dvui.flexbox(@src(), .{}, .{ .expand = .horizontal });
            defer header_box.deinit();
            dvui.label(@src(), "Dependency count: {d}", .{app.package.packages.count()}, .{ .expand = .horizontal });
        }

        if (root.dependencies) |packages| {
            var packages_it = packages.iterator();
            var i: u64 = 0;
            while (packages_it.next()) |pkg| {
                const package_name = pkg.key_ptr.*;

                // Set this as the selected package if clicked.
                const clicked = dvui.expander(@src(), package_name, .{}, .{ .expand = .horizontal, .id_extra = i });
                if (clicked) {
                    // Show a box with this package's dependencies in it.
                    const hash = std.hash.Adler32.hash(package_name);
                    const box = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = hash, .margin = dvui.Rect{ .x = 20, .y = 0, .w = 0, .h = 0 } });
                    defer box.deinit();

                    // Find the package and list its dependencies.
                    const allocator = arena_allocator.allocator();
                    const node_modules_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "node_modules/", package_name });
                    if (app.package.packages.get(node_modules_path)) |node_modules_package| {
                        if (node_modules_package.dependencies) |node_modules_dependencies| {
                            var node_module_dependencies_it = node_modules_dependencies.iterator();
                            while (node_module_dependencies_it.next()) |dependency| {
                                const dependency_name = dependency.key_ptr.*;
                                const dependency_value = dependency.value_ptr.*;

                                // See if we can find the actual package's version that's install.
                                var actual_dependency_version: ?[]const u8 = undefined;
                                actual: {
                                    const pkg_dep_full_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "node_modules/", dependency_name });
                                    const pkg_dep_sub_pkg_full_name = try std.mem.concat(allocator, u8, &[_][]const u8{ node_modules_path, "/", pkg_dep_full_name });

                                    // First check to see if this package exists in this package's node_modules_folder.
                                    // This could mean that there's another version that's conflicting at the package
                                    // level and this package has a different version of its dependency.
                                    if (app.package.packages.get(pkg_dep_sub_pkg_full_name)) |actual| {
                                        actual_dependency_version = actual.version;
                                        break :actual;
                                    }

                                    // Check the top node_modules folder to see if the dependency is shared.
                                    if (app.package.packages.get(pkg_dep_full_name)) |actual| {
                                        actual_dependency_version = actual.version;
                                        break :actual;
                                    }

                                    // Fall back showing something. This means that we couldn't find it and it's probably a bug.
                                    actual_dependency_version = "N/A";
                                }

                                // TODO: This is not really a reliable way to produce a unique
                                // hash. Adler32 only takes the first 16 characters when
                                // generating a hash, so long package names collide. The quick
                                // fix here is to instead start with the semver number here
                                // which is less likely to collide with the package name right
                                // after it.
                                const unique_name = try std.mem.concat(allocator, u8, &[_][]const u8{ dependency_value, dependency_name });
                                const pkg_dep_hash = std.hash.Adler32.hash(unique_name);

                                {
                                    const pkg_dep_box = dvui.flexbox(@src(), .{ .justify_content = .start }, .{ .expand = .horizontal, .id_extra = pkg_dep_hash });
                                    defer pkg_dep_box.deinit();
                                    dvui.label(@src(), "{s}", .{dependency_name}, .{ .expand = .horizontal });
                                    dvui.label(@src(), "Required: {s}", .{dependency_value}, .{ .expand = .horizontal });
                                    if (actual_dependency_version) |actual| {
                                        dvui.label(@src(), "Actual: {s}", .{actual}, .{ .expand = .horizontal });
                                    }
                                }
                            }
                        } else {
                            dvui.label(@src(), "This package has no dependencies.", .{}, .{ .expand = .horizontal });
                        }
                    }
                }

                i += 1;
            }
        }
    }

    return .ok;
}
