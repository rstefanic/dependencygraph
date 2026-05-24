const std = @import("std");
const assert = std.debug.assert;

pub const Package = struct {
    version: ?[]const u8 = null,
    resolved: ?[]const u8 = null,
    integrity: ?[]const u8 = null,
    link: ?bool = null,
    dev: ?bool = null,
    optional: ?bool = null,
    dev_optional: ?bool = null,
    in_bundle: ?bool = null,
    has_install_script: ?bool = null,
    has_shrinkwrap: ?bool = null,
    license: ?[]const u8 = null,

    bin: ?std.StringHashMap([]const u8) = null,
    engines: ?std.StringHashMap([]const u8) = null,

    dependencies: ?std.StringHashMap([]const u8) = null,
    dev_dependencies: ?std.StringHashMap([]const u8) = null,
    peer_dependencies: ?std.StringHashMap([]const u8) = null,
    optional_dependencies: ?std.StringHashMap([]const u8) = null,

    pub fn deinit(self: *Package) void {
        if (self.bin) |*bin| {
            bin.deinit();
        }

        if (self.engines) |*engines| {
            engines.deinit();
        }

        if (self.dependencies) |*dependencies| {
            dependencies.deinit();
        }

        if (self.dev_dependencies) |*dev_dependencies| {
            dev_dependencies.deinit();
        }

        if (self.peer_dependencies) |*peer_dependencies| {
            peer_dependencies.deinit();
        }

        if (self.optional_dependencies) |*optional_dependencies| {
            optional_dependencies.deinit();
        }
    }
};

pub const LockFile = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    lockfile_version: i64,
    requires: bool,
    packages: std.StringHashMap(Package),

    pub fn init(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !LockFile {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
        defer file.close(io);

        const stat = try file.stat(io);
        const size = stat.size;
        const buffer = try allocator.alloc(u8, size);

        _ = try file.readPositionalAll(io, buffer, 0);

        // Grab the base object
        const json = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        const package = json.value.object;

        // Pull out the top level properties
        const name = package.get("name").?.string;
        const version = package.get("version").?.string;
        const lockfile_version = package.get("lockfileVersion").?.integer;
        const requires = package.get("requires").?.bool;

        if (lockfile_version != 3) {
            return error.LockfileVersionNotSupported;
        }

        const packages_obj = package.get("packages") orelse {
            return error.MissingPackagesField;
        };

        var packages_it = packages_obj.object.iterator();
        var packages = std.StringHashMap(Package).init(allocator);
        errdefer packages.deinit();

        while (packages_it.next()) |pkg| {
            const pkg_key = pkg.key_ptr.*;
            var pkg_name = if (std.mem.eql(u8, pkg_key, "")) "root" else pkg_key;

            // Drop the leading "node_modules/" from the name if it exists.
            if (std.mem.startsWith(u8, pkg_name, "node_modules/")) {
                pkg_name = pkg_name[13..];
            }

            assert(pkg.value_ptr.* == .object);
            const dep_obj = pkg.value_ptr.*.object;

            var dep = Package{
                .version = if (dep_obj.get("version")) |dep_version| dep_version.string else null,
                .resolved = if (dep_obj.get("resolved")) |resolved| resolved.string else null,
                .integrity = if (dep_obj.get("integrity")) |integrity| integrity.string else null,
                .link = if (dep_obj.get("link")) |link| link.bool else null,
                .dev = if (dep_obj.get("dev")) |dev| dev.bool else null,
                .optional = if (dep_obj.get("optional")) |optional| optional.bool else null,
                .dev_optional = if (dep_obj.get("dev_optional")) |dev_optional| dev_optional.bool else null,
                .in_bundle = if (dep_obj.get("in_bundle")) |in_bundle| in_bundle.bool else null,
                .has_install_script = if (dep_obj.get("has_install_script")) |has_install_script| has_install_script.bool else null,
                .has_shrinkwrap = if (dep_obj.get("has_shrinkwrap")) |has_shrinkwrap| has_shrinkwrap.bool else null,
                .license = if (dep_obj.get("license")) |license| license.string else null,
            };

            try addHashmapIfFieldExists(allocator, &dep.bin, dep_obj.get("bin"));
            try addHashmapIfFieldExists(allocator, &dep.engines, dep_obj.get("engines"));

            try addHashmapIfFieldExists(allocator, &dep.dependencies, dep_obj.get("dependencies"));
            try addHashmapIfFieldExists(allocator, &dep.dev_dependencies, dep_obj.get("devDependencies"));
            try addHashmapIfFieldExists(allocator, &dep.peer_dependencies, dep_obj.get("peerDependencies"));
            try addHashmapIfFieldExists(allocator, &dep.optional_dependencies, dep_obj.get("optionalDependencies"));

            try packages.put(pkg_name, dep);
        }

        return .{ .allocator = allocator, .name = name, .version = version, .lockfile_version = lockfile_version, .requires = requires, .packages = packages };
    }

    /// If the JSON object passed in exists, then a StringHashMap will be
    /// allocated at the `hashmap` location given and filled with the value
    /// from the JSON object.
    fn addHashmapIfFieldExists(allocator: std.mem.Allocator, hashmap: *?std.StringHashMap([]const u8), maybe_field: ?std.json.Value) !void {
        if (maybe_field) |field| {
            assert(field == .object or field == .array);

            hashmap.* = std.StringHashMap([]const u8).init(allocator);
            errdefer hashmap.*.?.deinit();

            switch (field) {
                .array => {
                    for (field.array.items, 0..) |element, i| {
                        var buf: [3]u8 = undefined;
                        const key = try std.fmt.bufPrint(&buf, "{}", .{i});

                        assert(element == .string);
                        try hashmap.*.?.put(key, element.string);
                    }
                },
                .object => {
                    var it = field.object.iterator();
                    while (it.next()) |entity| {
                        const name = entity.key_ptr.*;
                        const version = entity.value_ptr.*.string; // TODO: Improve deserialization here
                        try hashmap.*.?.put(name, version);
                    }
                },
                else => unreachable,
            }
        }
    }

    pub fn deinit(self: *LockFile) void {
        var it = self.packages.iterator();
        while (it.next()) |pkg| {
            pkg.value_ptr.*.deinit();
        }
    }
};
