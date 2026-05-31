const std = @import("std");
const assert = std.debug.assert;
const dvui = @import("dvui");

const dependencyGraph = @import("dependencygraph");
const Package = dependencyGraph.Package;

const App = @This();
const MAX_SEARCH_RESULTS_LEN: u32 = 25;

lockfile: dependencyGraph.LockFile = undefined,
arena_allocator: ?std.heap.ArenaAllocator = undefined,

// Search fields
search_show: bool = false,
search_buf: [256]u8 = undefined,
search_buf_len: u32 = 0,
search_focus: bool = false,
search_results: [MAX_SEARCH_RESULTS_LEN][]const u8 = undefined,
search_results_len: u32 = 0,

// History and package view
selection_active: []const u8,
selection_history: std.ArrayList([]const u8) = .empty,

pub fn packageTrees(self: *App, root: Package) !dvui.App.Result {
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
                .devDependencies => "Developer Dependencies",
                .peerDependencies => "Peer Dependencies",
                .optionalDependencies => "Optional Dependencies",
            };
        }

        pub fn dependenciesByType(pt: PackageType, package: Package) ?std.StringHashMap([]const u8) {
            return switch (pt) {
                .dependencies => package.dependencies,
                .devDependencies => package.dev_dependencies,
                .peerDependencies => package.peer_dependencies,
                .optionalDependencies => package.optional_dependencies,
            };
        }
    };

    // Add a tab for each package type that we have (e.g. dependencies, dev dependencies, etc.)
    const tabs_box = dvui.box(@src(), .{}, .{ .expand = .both });
    defer tabs_box.deinit();
    {
        var tabs = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .padding = dvui.Rect{ .x = 10, .y = 10, .w = 10, .h = 10 } });
        defer tabs.deinit();

        const allocator = self.arena_allocator.?.allocator();
        for (0..PackageType.num_tabs) |i| {
            const package_type_tab: PackageType = @enumFromInt(i);

            // Check the dependencies to get a count of how many we have byt his type.
            var dependencies_count: u32 = 0;
            const dependencies = local.dependenciesByType(package_type_tab, root);
            if (dependencies) |deps| {
                assert(deps.count() < 999);
                dependencies_count = deps.count();
            }

            // Convert the count into a string.
            var tmp: [3]u8 = undefined;
            const count = try std.fmt.bufPrint(&tmp, "{}", .{dependencies_count});

            // Add the label to this tab and handle click selected.
            const tab_label = try std.mem.concat(allocator, u8, &[_][]const u8{ local.name(package_type_tab), " (", count, ")" });
            const selected = tabs.addTabLabel(local.isSelected(package_type_tab), tab_label, .{});
            if (selected) {
                local.selected = package_type_tab;
            }
        }
    }

    const selected_packages = local.dependenciesByType(local.selected, root);
    if (selected_packages) |packages| {
        return self.packageDependencies(packages);
    } else {
        dvui.label(@src(), "This package has no {s}.", .{local.name(local.selected)}, .{});
    }

    return .ok;
}

pub fn packageDependencies(self: *App, packages: std.StringHashMap([]const u8)) !dvui.App.Result {
    var packages_it = packages.iterator();
    var i: u64 = 0;
    const allocator = self.arena_allocator.?.allocator();

    while (packages_it.next()) |pkg| {
        const package_name = pkg.key_ptr.*;
        const resolved = try self.lockfile.resolvePackageByName(allocator, package_name, null);
        const version = if (resolved.package.version) |version| version else "N/A";

        // Set this as the selected package if clicked.
        const package_label = try std.mem.concat(allocator, u8, &[_][]const u8{ resolved.path, " (", version, ")" });
        const clicked = dvui.expander(@src(), package_label, .{}, .{ .expand = .horizontal, .id_extra = i });
        if (clicked) {
            // Show a box with this package's dependencies in it.
            const hash = std.hash.Adler32.hash(package_name);
            const box = dvui.box(@src(), .{}, .{ .expand = .horizontal, .id_extra = hash, .margin = dvui.Rect{ .x = 20, .y = 0, .w = 0, .h = 0 } });
            defer box.deinit();

            // Find the package and list its dependencies.
            if (self.lockfile.packages.get(package_name)) |node_modules_package| {
                if (node_modules_package.dependencies) |node_modules_dependencies| {
                    var node_module_dependencies_it = node_modules_dependencies.iterator();
                    while (node_module_dependencies_it.next()) |dependency| {
                        try self.drawPackageDependencyLabels(allocator, package_name, dependency);
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

fn drawPackageDependencyLabels(self: *App, allocator: std.mem.Allocator, parent_package_name: []const u8, dependency: std.StringHashMap([]const u8).Entry) !void {
    const dependency_name = dependency.key_ptr.*;
    const dependency_value = dependency.value_ptr.*;

    if (self.lockfile.resolvePackageByName(allocator, dependency_name, parent_package_name)) |resolved| {
        // TODO: This is not really a reliable way to produce a unique hash. Adler32 only takes the first 16
        // characters when generating a hash, so long package names collide. The quick fix here is to instead
        // start with the semver number here which is less likely to collide with the package name right after it.
        const unique_name = try std.mem.concat(allocator, u8, &[_][]const u8{ dependency_value, dependency_name });
        const pkg_dep_hash = std.hash.Adler32.hash(unique_name);
        const pkg_dep_box = dvui.flexbox(@src(), .{ .justify_content = .start }, .{ .expand = .horizontal, .id_extra = pkg_dep_hash });
        defer pkg_dep_box.deinit();
        const label_clicked = dvui.labelClick(@src(), "{s}", .{dependency_name}, .{}, .{ .expand = .horizontal });
        dvui.label(@src(), "Required: {s}", .{dependency_value}, .{ .expand = .horizontal });
        if (resolved.package.version) |version| {
            dvui.label(@src(), "Actual: {s}", .{version}, .{ .expand = .horizontal });
        }

        if (resolved.package.license) |license| {
            dvui.label(@src(), "License: {s}", .{license}, .{ .expand = .horizontal });
        }

        if (label_clicked) {
            try self.selection_history.append(allocator, resolved.path);
            self.selection_active = resolved.path;
        }
    } else |_| {
        // If we can't resolve the package, then show an error message.
        dvui.label(@src(), "ERR: \"{s}\" not found", .{dependency_name}, .{ .expand = .horizontal });
    }
}
