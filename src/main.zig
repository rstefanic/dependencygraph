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

    const parsed_package = try dependencygraph.readPackageJson(allocator, "package-lock.json");
    defer parsed_package.deinit();

    const packages = parsed_package.value.object.get("packages") orelse {
        std.debug.print("Error: Missing 'packages' property\n", .{});
        return error.InvalidJson;
    };

    var it = packages.object.iterator();
    while (it.next()) |entry| {
        // Handle root package name
        const key = entry.key_ptr.*;
        if (std.mem.eql(u8, key, "")) {
            std.debug.print("[root]:\n", .{});
        } else {
            std.debug.print("{s}:\n", .{entry.key_ptr.*});
        }

        assert(entry.value_ptr.* == .object);
        var obj_it = entry.value_ptr.*.object.iterator();

        while (obj_it.next()) |kv| {
            std.debug.print("\t{s}: ", .{kv.key_ptr.*});
            switch (kv.value_ptr.*) {
                .bool => |b| std.debug.print("{}", .{b}),
                .integer => |n| std.debug.print("{d}", .{n}),
                .float => |n| std.debug.print("{d}", .{n}),
                .number_string, .string => |s| std.debug.print("{s}", .{s}),
                .array => std.debug.print("[Array]", .{}),
                .object => std.debug.print("[Object]", .{}),
                else => std.debug.print("NULL", .{}),
            }

            std.debug.print("\n", .{});
        }
    }

    try stdout.flush(); // Don't forget to flush!
}
