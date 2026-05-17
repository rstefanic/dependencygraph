const std = @import("std");
const dvui = @import("dvui");

const App = @import("App.zig");

const Search = @This();

pub fn frame(app: *App) void {
    for (dvui.events()) |e| {
        switch (e.evt) {
            .key => {
                const key = e.evt.key.code;
                if (!app.show_search and key == .slash) {
                    app.show_search = true;
                    app.focus_search = true;
                } else if (app.show_search and key == .escape) {
                    @memset(&app.search_buf, 0); // reset the search value
                    app.show_search = false;
                }
            },
            else => break,
        }
    }

    if (app.show_search) {
        renderSearch(app);
    }
}

fn renderSearch(app: *App) void {
    var floating_window_rect: dvui.Rect = .cast(dvui.windowRect().insetAll(32));
    var floating_window = dvui.floatingWindow(
        @src(),
        .{ .resize = .none, .rect = &floating_window_rect, .stay_above_parent_window = true, .modal = true },
        .{},
    );
    defer floating_window.deinit();

    var hbox = dvui.box(@src(), .{}, .{ .expand = .horizontal });
    defer hbox.deinit();
    {
        var search = dvui.textEntry(@src(), .{ .text = .{ .buffer = &app.search_buf }, .placeholder = "Search for a package..." }, .{ .expand = .horizontal });
        defer search.deinit();

        if (app.focus_search) {
            app.focus_search = false;
            dvui.focusWidget(search.wd.id, null, null);
        }
    }
}
