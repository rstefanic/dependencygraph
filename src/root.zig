const std = @import("std");

const PackageJson = struct {
    name: []const u8,
    version: []const u8,
    lockfileVersion: u8,
    requires: bool,
};

pub fn readPackageJson(allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(std.json.Value) {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, size);
    _ = try file.readAll(buffer);

    return std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
}
