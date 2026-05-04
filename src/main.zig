const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const dependencygraph = @import("dependencygraph");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var package = try dependencygraph.Package.init(io, allocator, "package-lock.json");
    defer package.deinit();

    if (package.packages.get("root")) |root| {
        if (root.dependencies) |dependencies| {
            var dep_it = dependencies.iterator();
            while (dep_it.next()) |pkg| {
                const name = pkg.key_ptr.*;
                const c_str = try allocator.dupeZ(u8, name);
                defer allocator.free(c_str);
            }
        }
    }

    try stdout.print("Dependencies count for {s}: {d}\n", .{ package.name, package.packages.count() });
    try stdout.flush(); // Don't forget to flush!
}
