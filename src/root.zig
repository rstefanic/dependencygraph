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

        // Read the file into a buffer.
        const stat = try file.stat(io);
        const size = stat.size;
        const buffer = try allocator.alloc(u8, size);
        _ = try file.readPositionalAll(io, buffer, 0);

        // Grab the base JSON object.
        const json = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        const lockfile = json.value.object;

        // Currently only support reading version 3 lockfiles.
        const lockfile_version = lockfile.get("lockfileVersion") orelse {
            return error.MissingLockfileVersion;
        };
        assert(lockfile_version == .integer);
        if (lockfile_version.integer != 3) {
            return error.LockfileVersionNotSupported;
        }

        // This is our hash map of packages by name.
        var packages = std.StringHashMap(Package).init(allocator);
        errdefer packages.deinit();

        // Iterate throught the "packages" object on the lockfile building
        // up our own model of it.
        const packages_json = lockfile.get("packages") orelse {
            return error.MissingPackagesField;
        };
        var packages_json_it = packages_json.object.iterator();
        while (packages_json_it.next()) |pkg| {
            assert(pkg.value_ptr.* == .object);

            const package_json = pkg.value_ptr.*.object;
            var package = Package{
                .version = if (package_json.get("version")) |version| version.string else null,
                .resolved = if (package_json.get("resolved")) |resolved| resolved.string else null,
                .integrity = if (package_json.get("integrity")) |integrity| integrity.string else null,
                .link = if (package_json.get("link")) |link| link.bool else null,
                .dev = if (package_json.get("dev")) |dev| dev.bool else null,
                .optional = if (package_json.get("optional")) |optional| optional.bool else null,
                .dev_optional = if (package_json.get("dev_optional")) |dev_optional| dev_optional.bool else null,
                .in_bundle = if (package_json.get("in_bundle")) |in_bundle| in_bundle.bool else null,
                .has_install_script = if (package_json.get("has_install_script")) |has_install_script| has_install_script.bool else null,
                .has_shrinkwrap = if (package_json.get("has_shrinkwrap")) |has_shrinkwrap| has_shrinkwrap.bool else null,
                .license = if (package_json.get("license")) |license| license.string else null,
            };

            // Parse out the objects on the package as hashmaps.
            try addHashmapIfFieldExists(allocator, &package.bin, package_json.get("bin"));
            try addHashmapIfFieldExists(allocator, &package.engines, package_json.get("engines"));
            try addHashmapIfFieldExists(allocator, &package.dependencies, package_json.get("dependencies"));
            try addHashmapIfFieldExists(allocator, &package.dev_dependencies, package_json.get("devDependencies"));
            try addHashmapIfFieldExists(allocator, &package.peer_dependencies, package_json.get("peerDependencies"));
            try addHashmapIfFieldExists(allocator, &package.optional_dependencies, package_json.get("optionalDependencies"));

            // Create the name that we can use to reference the package.
            const package_name = pkg.key_ptr.*;
            // The empty package name is the root package. While this is a valid JSON key,
            // it's weird and I prefer calling it the root package.
            var name = if (std.mem.eql(u8, package_name, "")) "root" else package_name;
            // Drop the leading "node_modules/" from the name if it exists.
            if (std.mem.startsWith(u8, name, "node_modules/")) {
                name = name[13..];
            }

            try packages.put(name, package);
        }

        // Grab high level information about the lockfile.
        const name = lockfile.get("name").?.string;
        const version = lockfile.get("version").?.string;
        const requires = lockfile.get("requires").?.bool;

        return .{ .allocator = allocator, .name = name, .version = version, .lockfile_version = lockfile_version.integer, .requires = requires, .packages = packages };
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
