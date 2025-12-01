const std = @import("std");
const assert = std.debug.assert;

const Dependency = struct {
    allocator: std.mem.Allocator,
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

    // TODO: Add these in (they're not strings)
    // bin: ?[]const u8 = null,
    // license: ?[]const u8 = null,
    // engines: ?[]const u8 = null,

    dependencies: std.StringHashMap([]const u8),
    optional_dependencies: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) !Dependency {
        var dependencies = std.StringHashMap([]const u8).init(allocator);
        errdefer dependencies.deinit();

        var optional_dependencies = std.StringHashMap([]const u8).init(allocator);
        errdefer optional_dependencies.deinit();

        return .{
            .allocator = allocator,
            .dependencies = dependencies,
            .optional_dependencies = optional_dependencies,
        };
    }

    pub fn deinit(self: *Dependency) void {
        self.dependencies.deinit();
        self.optional_dependencies.deinit();
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
            var dep = try Dependency.init(allocator);

            assert(pkg.value_ptr.* == .object);
            const dep_obj = pkg.value_ptr.*.object;

            dep.version = if (dep_obj.get("version")) |dep_version| dep_version.string else null;
            dep.resolved = if (dep_obj.get("resolved")) |resolved| resolved.string else null;
            dep.integrity = if (dep_obj.get("integrity")) |integrity| integrity.string else null;
            dep.link = if (dep_obj.get("link")) |link| link.bool else null;
            dep.dev = if (dep_obj.get("dev")) |dev| dev.bool else null;
            dep.optional = if (dep_obj.get("optional")) |optional| optional.bool else null;
            dep.dev_optional = if (dep_obj.get("dev_optional")) |dev_optional| dev_optional.bool else null;
            dep.in_bundle = if (dep_obj.get("in_bundle")) |in_bundle| in_bundle.bool else  null;
            dep.has_install_script = if (dep_obj.get("has_install_script")) |has_install_script| has_install_script.bool else null;
            dep.has_shrinkwrap = if (dep_obj.get("has_shrinkwrap")) |has_shrinkwrap| has_shrinkwrap.bool else null;

            try packages.put(pkg_name, dep);
        }

        return .{
            .allocator = allocator,
            .name = name,
            .version = version,
            .lockfileVersion = lockfileVersion,
            .requires = requires,
            .packages = packages
        };
    }

    pub fn deinit(self: *Package) void {
        var it = self.packages.iterator();
        while (it.next()) |pkg| {
            pkg.value_ptr.*.deinit();
        }
    }
};
