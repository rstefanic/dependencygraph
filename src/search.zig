const std = @import("std");
const dvui = @import("dvui");

const App = @import("App.zig");

const Search = @This();

pub fn frame(app: *App) !void {
    for (dvui.events()) |e| {
        switch (e.evt) {
            .key => {
                const key = e.evt.key.code;
                if (!app.search_show and key == .slash) {
                    show(app);
                } else if (app.search_show and key == .escape) {
                    hide(app);
                }
            },
            else => break,
        }
    }

    if (app.search_show) {
        try renderSearch(app);
    }
}

fn show(app: *App) void {
    app.search_show = true;
    app.search_focus = true;
}

fn hide(app: *App) void {
    @memset(&app.search_buf, 0); // reset the search value
    app.search_show = false;
}

fn renderSearch(app: *App) !void {
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
        var search_box = dvui.textEntry(@src(), .{ .text = .{ .buffer = &app.search_buf }, .placeholder = "Search for a package..." }, .{ .expand = .horizontal });
        defer search_box.deinit();

        if (app.search_focus) {
            app.search_focus = false;
            dvui.focusWidget(search_box.wd.id, null, null);
        }
    }

    const scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    // Run the search and stores the results in `app.search_resuts`.
    doSearch(app);
    for (app.search_results, 0..) |result, i| {
        const label_clicked = dvui.labelClick(@src(), "{s}", .{result}, .{}, .{ .expand = .horizontal, .id_extra = i });
        if (label_clicked) {
            const allocator = app.arena_allocator.?.allocator();
            try app.selection_history.append(allocator, result);
            app.selection_active = result;
            hide(app);
        }
    }

    if (app.search_show) {
        // See if the user is trying to navigate the selection here. These
        // key code events are handled here so that `tabIndex*` functions work
        // within the context of this window.
        for (dvui.events()) |e| {
            switch (e.evt) {
                .key => |key| {
                    if (key.code == .up and key.action == .up) {
                        dvui.tabIndexPrev(null);
                    } else if (key.code == .down and key.action == .up) {
                        dvui.tabIndexNext(null);
                    }
                },
                else => break,
            }
        }
    }
}

fn doSearch(app: *App) void {
    var i: u32 = 0;

    // Trim trailing whitespace and null bytes.
    const term = std.mem.trim(u8, &app.search_buf, " \t\r\n\x00");

    var it = app.lockfile.packages.iterator();
    while (it.next()) |pkg| {
        const name = pkg.key_ptr.*;
        if (std.mem.indexOf(u8, name, term) != null) {
            app.search_results[i] = name;
            i += 1;
        }

        if (i == 25) break;
    }
}
