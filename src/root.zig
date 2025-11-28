const std = @import("std");

const PackageJson = struct {
    name: []const u8,
    version: []const u8,
    lockfileVersion: u8,
    requires: bool,
};

pub fn readPackageJson(allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(std.json.Value) {
    const buffer = try allocator.alloc(u8, 512);
    defer allocator.free(buffer);
    const data = try std.fs.cwd().readFile(path, buffer);

    return std.json.parseFromSlice(std.json.Value, allocator, data, .{});
}
