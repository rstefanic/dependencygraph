const std = @import("std");
const dvui = @import("dvui");

const dependencyGraph = @import("dependencygraph");
const Dependency = dependencyGraph.Dependency;

const App = @This();

package: dependencyGraph.Package = undefined,
arena_allocator: ?std.heap.ArenaAllocator = undefined,

pub fn packageTrees(self: *App, root: Dependency) !dvui.App.Result {
    const PackageType = enum {
        dependencies,
        devDependencies,
        peerDependencies,
        optionalDependencies,
        const num_tabs = @typeInfo(@This()).@"enum".fields.len;
    };

    const local = struct {
        var selected: PackageType = .dependencies;

        pub fn isSelected(packageType: PackageType) bool {
            return selected == packageType;
        }

        pub fn name(packageType: PackageType) []const u8 {
            return switch (packageType) {
                .dependencies => "Dependencies",
                .devDependencies => "Dev Dependencies",
                .peerDependencies => "Peer Dependencies",
                .optionalDependencies => "Optional Dependencies",
            };
        }
    };

    const tabs_box = dvui.box(@src(), .{}, .{ .expand = .both });
    defer tabs_box.deinit();
    {
        var tabs = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .padding = dvui.Rect{ .x = 10, .y = 10, .w = 10, .h = 10 } });
        defer tabs.deinit();

        for (0..PackageType.num_tabs) |i| {
            const tab: PackageType = @enumFromInt(i);

            const selected = tabs.addTabLabel(local.isSelected(tab), local.name(tab), .{});
            if (selected) {
                local.selected = tab;
            }
        }
    }

    switch (local.selected) {
        .dependencies => {
            if (root.dependencies) |packages| {
                return self.packageDependencies(packages);
            } else {
                dvui.label(@src(), "This package has no Dependencies.", .{}, .{});
            }
        },
        .devDependencies => {
            if (root.dev_dependencies) |packages| {
                return self.packageDependencies(packages);
            } else {
                dvui.label(@src(), "This package has no Developer Dependencies.", .{}, .{});
            }
        },
        .peerDependencies => {
            if (root.peer_dependencies) |packages| {
                return self.packageDependencies(packages);
            } else {
                dvui.label(@src(), "This package has no Peer Dependencies.", .{}, .{});
            }
        },
        .optionalDependencies => {
            if (root.optional_dependencies) |packages| {
                return self.packageDependencies(packages);
            } else {
                dvui.label(@src(), "This package has no Optional Dependencies.", .{}, .{});
            }
        },
    }

    return .ok;
}

pub fn packageDependencies(self: *App, packages: std.StringHashMap([]const u8)) !dvui.App.Result {
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
            const allocator = self.arena_allocator.?.allocator();
            const node_modules_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "node_modules/", package_name });
            if (self.package.packages.get(node_modules_path)) |node_modules_package| {
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
                            if (self.package.packages.get(pkg_dep_sub_pkg_full_name)) |actual| {
                                actual_dependency_version = actual.version;
                                break :actual;
                            }

                            // Check the top node_modules folder to see if the dependency is shared.
                            if (self.package.packages.get(pkg_dep_full_name)) |actual| {
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

    return .ok;
}
