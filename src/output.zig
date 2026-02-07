const std = @import("std");

pub fn colorize(comptime color: Color, text: []const u8, use_color: bool) []const u8 {
    if (!use_color) return text;
    return switch (color) {
        .red => "\x1b[31m" ++ text ++ "\x1b[0m",
        .green => "\x1b[32m" ++ text ++ "\x1b[0m",
        .magenta => "\x1b[35m" ++ text ++ "\x1b[0m",
        .cyan => "\x1b[36m" ++ text ++ "\x1b[0m",
    };
}

pub const Color = enum {
    red,
    green,
    magenta,
    cyan,
};

pub fn writeColored(
    writer: anytype,
    text: []const u8,
    color: Color,
    use_color: bool,
) !void {
    if (use_color) {
        const color_code = switch (color) {
            .red => "31",
            .green => "32",
            .magenta => "35",
            .cyan => "36",
        };
        try writer.print("\x1b[{s}m{s}\x1b[0m", .{ color_code, text });
    } else {
        try writer.writeAll(text);
    }
}

pub fn isTty() bool {
    return std.fs.File.stdout().isTty();
}
