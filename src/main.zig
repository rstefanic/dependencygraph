const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const dependencygraph = @import("dependencygraph");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var package = try dependencygraph.Package.init(allocator, "package-lock.json");
    defer package.deinit();

    try stdout.flush(); // Don't forget to flush!
}
