const std = @import("std");
const vaxis = @import("vaxis");
const options = @import("../options.zig");

const App = @import("app.zig").App;

pub const Event = @import("app.zig").Event;

pub fn run(allocator: std.mem.Allocator, args: options.Args) !void {
    _ = args;

    var tty_buf: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buf);
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_ms);

    var app = try App.init(allocator);
    defer app.deinit();

    // Initial render
    try app.draw(vx.window());
    try vx.render(tty.writer());

    while (!app.should_quit) {
        const event = loop.nextEvent();

        // Handle resize events
        switch (event) {
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            else => {},
        }

        try app.update(event);
        try app.draw(vx.window());
        try vx.render(tty.writer());
    }
}
