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

/// Models what's needed from a package-lock.json. The raw JSON is stored here as `buffer`
/// and the strings used in the `packages` hashmap are slices into underlying JSON data.
/// JSON buffer and package strings share a lifetime and must be kept alive until done.
pub const LockFile = struct {
    allocator: std.mem.Allocator,
    buffer: []u8, // pointer to the raw JSON data
    packages: std.StringHashMap(Package), // package lookup by name
    name: []const u8,
    version: []const u8,
    lockfile_version: i64,
    requires: bool,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !LockFile {
        // Parse the lockfile as JSON.
        const buffer = try readLockfile(allocator, io, path);
        const json = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        assert(json.value == .object);

        const lockfile = json.value.object;
        try validateLockfileVersion(lockfile);

        // This is our hash map of packages by name.
        var packages = std.StringHashMap(Package).init(allocator);
        errdefer packages.deinit();

        // Parse the packages field.
        const packages_json = lockfile.get("packages") orelse {
            return error.MissingPackagesField;
        };
        assert(packages_json == .object);
        try parsePackages(allocator, &packages, packages_json.object);

        // Grab high level information about the lockfile.
        const name_json = lockfile.get("name") orelse {
            return error.LockfileMissingNameField;
        };
        const version_json = lockfile.get("version") orelse {
            return error.LockfileMissingVersionField;
        };
        const requires_json = lockfile.get("requires") orelse {
            return error.LockfileMissingRequiresField;
        };

        assert(name_json == .string);
        assert(version_json == .string);
        assert(requires_json == .bool);

        const name = name_json.string;
        const version = version_json.string;
        const requires = requires_json.bool;

        // zig fmt: off
        return .{
            .allocator = allocator,
            .buffer = buffer,
            .name = name,
            .version = version,
            .lockfile_version = lockfile.get("lockfileVersion").?.integer,
            .requires = requires,
            .packages = packages
        };
    }

    fn readLockfile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
        defer file.close(io);

        // Read the file into a buffer.
        const stat = try file.stat(io);
        const size = stat.size;
        const buffer = try allocator.alloc(u8, size);
        _ = try file.readPositionalAll(io, buffer, 0);
        return buffer;
    }

    fn validateLockfileVersion(lockfile_json: std.json.ObjectMap) !void {
        // Currently only support reading version 3 lockfiles.
        const lockfile_version = lockfile_json.get("lockfileVersion") orelse {
            return error.MissingLockfileVersion;
        };
        assert(lockfile_version == .integer);
        if (lockfile_version.integer != 3) {
            return error.LockfileVersionNotSupported;
        }
    }

    fn parsePackages(allocator: std.mem.Allocator, packages: *std.StringHashMap(Package), packages_json: std.json.ObjectMap) !void {
        var packages_json_it = packages_json.iterator();
        while (packages_json_it.next()) |pkg| {
            assert(pkg.value_ptr.* == .object);
            const package_name = pkg.key_ptr.*;
            const package_json = pkg.value_ptr.*.object;

            var package = Package{
                .version = null, // See code block below on handling version being null.
                .resolved = if (package_json.get("resolved")) |resolved| resolved: {
                    assert(resolved == .string);
                    break :resolved resolved.string;
                } else null,
                .integrity = if (package_json.get("integrity")) |integrity| integrity.string else null,
                .link = if (package_json.get("link")) |link| link: {
                    assert(link == .bool);
                    break :link link.bool;
                } else null,
                .dev = if (package_json.get("dev")) |dev| dev.bool else null,
                .optional = if (package_json.get("optional")) |optional| optional.bool else null,
                .dev_optional = if (package_json.get("dev_optional")) |dev_optional| dev_optional.bool else null,
                .in_bundle = if (package_json.get("in_bundle")) |in_bundle| in_bundle.bool else null,
                .has_install_script = if (package_json.get("has_install_script")) |has_install_script| has_install_script.bool else null,
                .has_shrinkwrap = if (package_json.get("has_shrinkwrap")) |has_shrinkwrap| has_shrinkwrap.bool else null,
                .license = if (package_json.get("license")) |license| license: {
                    assert(license == .string);
                    break :license license.string;
                } else null,
            };

            // Depending on the package type, it will determine which fields are required when parsing the lockfile.
            // Fileds that we heavily rely on are asserted to be the expected type.
            const package_classification = classifyPackage(package_name);
            const version_field_required = packageRequiresVersionMetadata(package_classification, &package);

            if (package_json.get("version")) |version| {
                assert(version == .string);
                package.version = version.string;
            } else if (version_field_required) {
                std.debug.print("Invalid package {s}\n", .{package_name});
                return error.MissingRequiredPackageVersion;
            }

            // Parse out the objects on the package as hashmaps.
            try addHashmapIfFieldExists(allocator, &package.bin, package_json.get("bin"));
            try addHashmapIfFieldExists(allocator, &package.engines, package_json.get("engines"));
            try addHashmapIfFieldExists(allocator, &package.dependencies, package_json.get("dependencies"));
            try addHashmapIfFieldExists(allocator, &package.dev_dependencies, package_json.get("devDependencies"));
            try addHashmapIfFieldExists(allocator, &package.peer_dependencies, package_json.get("peerDependencies"));
            try addHashmapIfFieldExists(allocator, &package.optional_dependencies, package_json.get("optionalDependencies"));

            // Create the name that we can use to reference the package.
            const name = switch (package_classification) {
                .root => "root",
                .node_module => package_name[13..],
                .local => package_name,
            };

            try packages.put(name, package);
        }
    }

    fn packageRequiresVersionMetadata(pc: PackageClassification, package: *Package) bool {
        switch (pc) {
            .root, .local => return false,
            .node_module => {
                // If it's a node_module and it's linked, then the 'version' metadata isn't required.
                if (package.link) |link| {
                    if (link) {
                        return false;
                    }
                }

                // If it doesn't have 'link', then check the 'resolved' metadata prefix.
                if (package.resolved) |resolved| {
                    if (std.mem.startsWith(u8, resolved, "file:")) {
                        return false;
                    }

                    if (std.mem.startsWith(u8, resolved, "workspace:")) {
                        return false;
                    }
                }

                // If we get here, then we need a 'version' otherwise the
                // package is invalid otherwise the package is invalid.
                return true;
            },
        }
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
                        assert(i < 999);
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

    const PackageClassification = enum {
        root,
        node_module,
        local,
    };

    fn classifyPackage(name: []const u8) PackageClassification {
        if (std.mem.eql(u8, name, "")) {
            return .root;
        }

        if (std.mem.startsWith(u8, name, "node_modules/")) {
            return .node_module;
        }

        return .local;
    }

    pub fn verify(self: *LockFile) bool {
        var it = self.packages.iterator();

        while (it.next()) |package| {
            const package_name = package.key_ptr;
            const value = package.value_ptr;

            if (value.dependencies) |dependencies| {
                if (!self.verifyDependencies(package_name, dependencies)) {
                    return false;
                }
            }
            if (value.dev_dependencies) |dev_dependencies| {
                if (!self.verifyDependencies(package_name, dev_dependencies)) {
                    return false;
                }
            }

            // TODO: Handle peer dependency check based on `peerDependenciesMeta` where it can be optional.
        }

        return true;
    }
    
    fn verifyDependencies(self: *LockFile, parent_package_name: *[]const u8, dependencies: std.StringHashMap([]const u8)) bool {
        var dependencies_it = dependencies.iterator();
        while (dependencies_it.next()) |dependency| {
            const dependency_name = dependency.key_ptr;
            _ = self.resolvePackageByName(self.allocator, dependency_name.*, parent_package_name.*) catch |err| switch (err) {
                error.NoPackageFound => {
                    std.debug.print("Missing \"{s}\" for \"{s}\"\n", .{dependency_name.*, parent_package_name.*});
                    return false;
                },
                else => {
                    std.debug.print("Unexpected error: {}\n", .{err});
                    return false;
                }
            }; 
        }

        return true;
    }

    const ResolvedPackage = struct { path: []const u8, package: *const Package };

    // TODO: Refactor another version of this that doesn't have the error. This
    // function is used here to verify that the Lockfile is valid, but it's also
    // used in the main program to show package names and their dependencies to
    // the user. We should have a version for the frontend that avoids throwing
    // the `error.NoPackageFound` error since if it's valid, then that error
    // can never happen at that point during runtime.
    //
    // Resolve the requested package based on the dependency and package name.
    pub fn resolvePackageByName(self: *LockFile, allocator: std.mem.Allocator, dependency_package_name: []const u8, parent_package_name: ?[]const u8) !ResolvedPackage {
        // First check to see if this package exists nested inthis package's node_modules folder. This
        // could mean that there's another version that's conflicting at the package level and this
        // package has a different version of its dependency.
        if (parent_package_name) |pp_name| {
            const nested_package_path = try std.mem.concat(allocator, u8, &[_][]const u8{ pp_name, "/node_modules/", dependency_package_name });
            if (self.packages.getPtr(nested_package_path)) |resolved_pkg| {
                return .{ .path = nested_package_path, .package = resolved_pkg };
            }
        }

        // Check the top node_modules folder to see if the dependency is shared.
        if (self.packages.getPtr(dependency_package_name)) |resolved_pkg| {
            return .{ .path = dependency_package_name, .package = resolved_pkg };
        }

        return error.NoPackageFound;
    }
};

