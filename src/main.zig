const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
});

const dependencygraph = @import("dependencygraph");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var package = try dependencygraph.Package.init(allocator, "package-lock.json");
    defer package.deinit();

    raylib.InitWindow(800, 450, "Dependency Graph");
    raylib.SetTargetFPS(60);


    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.RAYWHITE);

        const x: c_int = 200;
        var y: c_int = 200;

        raylib.DrawText("Dependencies", x, y, 24, raylib.LIGHTGRAY);
        y += 25;

        if (package.packages.get("root")) |root| {
            if (root.dependencies) |dependencies| {
                var dep_it = dependencies.iterator();
                while (dep_it.next()) |pkg| {
                    const name = pkg.key_ptr.*;
                    const c_str = try allocator.dupeZ(u8, name);
                    defer allocator.free(c_str);
                    raylib.DrawText(c_str.ptr, x, y, 18, raylib.LIGHTGRAY);
                    y += 20;
                }
            }
        }

        raylib.EndDrawing();
    }

    raylib.CloseWindow();

    try stdout.print("Dependencies count for {s}: {d}\n", .{ package.name, package.packages.count() });
    try stdout.flush(); // Don't forget to flush!
}
