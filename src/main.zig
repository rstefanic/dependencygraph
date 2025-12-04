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

    if (package.packages.get("root")) |root| {
        if (root.dependencies) |dependencies| {
            var dep_it = dependencies.iterator();
            try stdout.print("Dependencies\n", .{});
            while (dep_it.next()) |pkg| {
                const name = pkg.key_ptr.*;
                try stdout.print("\t{s}\n", .{name});
            }
        }

        if (root.dev_dependencies) |dev_dependencies| {
            var dev_it = dev_dependencies.iterator();
            try stdout.print("Dev Dependencies\n", .{});
            while (dev_it.next()) |pkg| {
                const name = pkg.key_ptr.*;
                try stdout.print("\t{s}\n", .{name});
            }
        }
    }

    try stdout.print("Dependencies count for {s}: {d}\n", .{ package.name, package.packages.count() });
    try stdout.flush(); // Don't forget to flush!
}
