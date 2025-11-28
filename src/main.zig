const std = @import("std");
const Allocator = std.mem.Allocator;

const dependencygraph = @import("dependencygraph");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var buffer: [2048]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const parsed_package = try dependencygraph.readPackageJson(allocator, "package-lock.json");
    defer parsed_package.deinit();

    try stdout.print("{s}!\n", .{ parsed_package.value.object.get("name").?.string });
    try stdout.flush(); // Don't forget to flush!
}
