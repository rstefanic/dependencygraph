const std = @import("std");
const assert = std.debug.assert;

const Dependency = struct {
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

    pub fn deinit(self: *Dependency) void {
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

pub const Package = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    lockfileVersion: i64,
    requires: bool,
    packages: std.StringHashMap(Dependency),

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Package {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        const size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, size);

        _ = try file.readAll(buffer);

        // Grab the base object
        const json = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        const package = json.value.object;

        // Pull out the top level properties
        const name = package.get("name").?.string;
        const version = package.get("version").?.string;
        const lockfileVersion = package.get("lockfileVersion").?.integer;
        const requires = package.get("requires").?.bool;

        if (lockfileVersion != 3) {
            return error.LockfileVersionNotSupported;
        }

        const packages_obj = package.get("packages") orelse {
            return error.MissingPackagesField;
        };

        var packages_it = packages_obj.object.iterator();
        var packages = std.StringHashMap(Dependency).init(allocator);
        errdefer packages.deinit();

        while (packages_it.next()) |pkg| {
            const pkg_key = pkg.key_ptr.*;
            const pkg_name = if (std.mem.eql(u8, pkg_key, "")) "root" else pkg_key;

            assert(pkg.value_ptr.* == .object);
            const dep_obj = pkg.value_ptr.*.object;

            var dep = Dependency{
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

            try addHashmapIfExists(allocator, &dep.bin, dep_obj.get("bin"));
            try addHashmapIfExists(allocator, &dep.engines, dep_obj.get("engines"));

            try addHashmapIfExists(allocator, &dep.dependencies, dep_obj.get("dependencies"));
            try addHashmapIfExists(allocator, &dep.dev_dependencies, dep_obj.get("devDependencies"));
            try addHashmapIfExists(allocator, &dep.peer_dependencies, dep_obj.get("peerDependencies"));
            try addHashmapIfExists(allocator, &dep.optional_dependencies, dep_obj.get("optionalDependencies"));

            try packages.put(pkg_name, dep);
        }

        return .{ .allocator = allocator, .name = name, .version = version, .lockfileVersion = lockfileVersion, .requires = requires, .packages = packages };
    }

    /// If the JSON object passed in exists, then a StringHashMap will be
    /// allocated at the `hashmap` location given and filled with the value
    /// from the JSON object.
    fn addHashmapIfExists(allocator: std.mem.Allocator, hashmap: *?std.StringHashMap([]const u8), maybe_json_obj: ?std.json.Value) !void {
        if (maybe_json_obj) |json_obj| {
            assert(json_obj == .object);

            hashmap.* = std.StringHashMap([]const u8).init(allocator);
            errdefer hashmap.*.?.deinit();

            var it = json_obj.object.iterator();
            while (it.next()) |entity| {
                const name = entity.key_ptr.*;
                const version = entity.value_ptr.*.string; // TODO: Improve deserialization here
                try hashmap.*.?.put(name, version);
            }
        }
    }

    pub fn deinit(self: *Package) void {
        var it = self.packages.iterator();
        while (it.next()) |pkg| {
            pkg.value_ptr.*.deinit();
        }
    }
};
