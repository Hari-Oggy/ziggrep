const std = @import("std");

pub const FileType = struct {
    name: []const u8,
    extensions: []const []const u8,
};

pub const definitions = [_]FileType{
    .{ .name = "c", .extensions = &.{ ".c", ".h" } },
    .{ .name = "cpp", .extensions = &.{ ".cpp", ".hpp", ".cc", ".cxx" } },
    .{ .name = "zig", .extensions = &.{ ".zig", ".zon" } },
    .{ .name = "python", .extensions = &.{".py"} },
    .{ .name = "js", .extensions = &.{ ".js", ".jsx", ".mjs", ".cjs" } },
    .{ .name = "ts", .extensions = &.{ ".ts", ".tsx" } },
    .{ .name = "java", .extensions = &.{".java"} },
    .{ .name = "go", .extensions = &.{".go"} },
    .{ .name = "rust", .extensions = &.{".rs"} },
    .{ .name = "html", .extensions = &.{ ".html", ".htm", ".css" } },
    .{ .name = "json", .extensions = &.{".json"} },
    .{ .name = "md", .extensions = &.{ ".md", ".markdown" } },
    .{ .name = "txt", .extensions = &.{ ".txt", ".text" } },
    .{ .name = "sh", .extensions = &.{ ".sh", ".bash", ".zsh" } },
};

pub fn getExtensions(type_name: []const u8) ?[]const []const u8 {
    for (definitions) |def| {
        if (std.mem.eql(u8, def.name, type_name)) {
            return def.extensions;
        }
    }
    return null;
}
