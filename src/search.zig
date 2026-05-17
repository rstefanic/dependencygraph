const std = @import("std");
const dvui = @import("dvui");

const App = @import("App.zig");

const Search = @This();

pub fn frame(app: *App) void {
    if (!app.show_search) {
        for (dvui.events()) |e| {
            switch (e.evt) {
                .key => {
                    if (e.evt.key.code == .slash) {
                        app.show_search = true;
                    }
                },
                else => break,
            }
        }
    }

    if (app.show_search) {
        renderSearch();
    }
}

fn renderSearch() void {
    var floating_window_rect: dvui.Rect = .cast(dvui.windowRect().insetAll(32));
    var floating_window = dvui.floatingWindow(
        @src(),
        .{ .resize = .none, .rect = &floating_window_rect, .stay_above_parent_window = true, .modal = true },
        .{},
    );
    defer floating_window.deinit();
}
