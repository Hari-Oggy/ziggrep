const std = @import("std");
const types = @import("types.zig");
const options = @import("options.zig");
const regex = @import("regex");
const glob = @import("glob.zig");
const ignore = @import("ignore.zig");

pub const WalkError = error{
    AccessDenied,
    pathNotFound,
    NameTooLong,
    SystemResources,
    Unexpected,
} || std.fs.File.OpenError || std.mem.Allocator.Error;

pub fn walkDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    opts: options.Options,
    callback: *const fn ([]const u8) anyerror!void,
) WalkError!void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Cannot open directory '{s}': {}\n", .{ dir_path, err });
        return;
    };
    defer dir.close();

    // Compile Globs
    var compiled_globs = std.ArrayList(regex.Regex).empty;
    defer {
        for (compiled_globs.items) |*re| re.deinit();
        compiled_globs.deinit(allocator);
    }

    for (opts.globs) |glob_pattern| {
        const pattern_str = try glob.globToRegex(allocator, glob_pattern);
        defer allocator.free(pattern_str);
        const re = regex.Regex.compile(allocator, pattern_str) catch |err| {
            std.debug.print("Invalid glob pattern '{s}': {}\n", .{ glob_pattern, err });
            return error.Unexpected;
        };
        try compiled_globs.append(allocator, re);
    }

    try walkRecursive(allocator, dir, dir_path, opts, compiled_globs.items, null, callback);
}

const IgnoreNode = struct {
    rules: []ignore.IgnoreRule,
    parent: ?*IgnoreNode,
    base_path: []const u8,
};

fn walkRecursive(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    current_path: []const u8,
    opts: options.Options,
    globs: []regex.Regex,
    parent_ignore: ?*IgnoreNode,
    callback: *const fn ([]const u8) anyerror!void,
) !void {
    // Parse .gitignore if at root or recursing
    // Note: If --hidden is NOT set, we respect gitignore? Or do we ALWAYS respect gitignore unless --no-ignore specified?
    // Standard ripgrep: respects gitignore by default.
    // Our spec: "Priority #8: .gitignore Support".
    // We assume enabled by default. Add --no-ignore later if needed.

    var ignore_rules: []ignore.IgnoreRule = &.{};
    // Only parse gitignore if NOT skipping hidden (implied "standard" mode) or explicit enabled?
    // Let's parse it always for now if we want robust support.

    ignore_rules = ignore.parseIgnoreFile(allocator, current_path) catch &.{};
    defer {
        for (ignore_rules) |*r| r.pattern.deinit();
        allocator.free(ignore_rules);
    }

    // Node on stack
    var current_node = IgnoreNode{
        .rules = ignore_rules,
        .parent = parent_ignore,
        .base_path = current_path,
    };

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        // Check for hidden files/dirs
        if (!opts.hidden and isHiddenFile(entry.name)) continue;

        const full_path = try std.fs.path.join(allocator, &.{ current_path, entry.name });
        defer allocator.free(full_path);

        // Check GitIgnore
        if (isIgnored(allocator, full_path, entry.kind == .directory, &current_node)) continue;

        switch (entry.kind) {
            .file => {
                // Check Filters (Type, Glob)
                if (!shouldProcessFile(entry.name, opts, globs)) continue;

                callback(full_path) catch |err| {
                    std.debug.print("Error processing '{s}': {}\n", .{ full_path, err });
                };
            },
            .directory => {
                var sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch |err| {
                    if (err == error.AccessDenied) {
                        continue;
                    }
                    return err;
                };
                defer sub_dir.close();

                try walkRecursive(allocator, sub_dir, full_path, opts, globs, &current_node, callback);
            },
            else => {},
        }
    }
}

fn isIgnored(allocator: std.mem.Allocator, full_path: []const u8, is_dir: bool, node_ptr: ?*IgnoreNode) bool {
    var curr = node_ptr;
    while (curr) |node| {
        // Relpath
        const rel_path = std.fs.path.relative(allocator, node.base_path, full_path) catch return false;
        defer allocator.free(rel_path);

        // Iterate rules in reverse order (bottom-up in file)
        var i = node.rules.len;
        while (i > 0) {
            i -= 1;
            // Get pointer to rule to access mutable pattern
            var rule = &node.rules[i];

            // Optimization
            if (rule.directory_only and !is_dir) continue;

            // Match
            var match_target: []const u8 = rel_path;
            if (rule.match_basename) {
                match_target = std.fs.path.basename(rel_path);
            }

            if (rule.pattern.match(match_target) catch false) {
                return !rule.negative;
            }
        }
        curr = node.parent;
    }
    return false;
}

fn shouldProcessFile(filename: []const u8, opts: options.Options, globs: []regex.Regex) bool {
    // 1. Type filtering (Include)
    if (opts.include_types.len > 0) {
        var matched_type = false;
        const ext = std.fs.path.extension(filename);
        for (opts.include_types) |type_name| {
            if (types.getExtensions(type_name)) |exts| {
                for (exts) |e| {
                    if (std.mem.eql(u8, ext, e)) {
                        matched_type = true;
                        break;
                    }
                }
            }
            if (matched_type) break;
        }
        if (!matched_type) return false;
    }

    // 2. Type filtering (Exclude)
    if (opts.exclude_types.len > 0) {
        const ext = std.fs.path.extension(filename);
        for (opts.exclude_types) |type_name| {
            if (types.getExtensions(type_name)) |exts| {
                for (exts) |e| {
                    if (std.mem.eql(u8, ext, e)) {
                        return false;
                    }
                }
            }
        }
    }

    // 3. Glob filtering
    if (globs.len > 0) {
        var matched_glob = false;
        for (globs) |*re| {
            if (re.match(filename) catch false) {
                matched_glob = true;
                break;
            }
        }
        if (!matched_glob) return false;
    }

    return true;
}

fn isHiddenFile(basename: []const u8) bool {
    return basename.len > 0 and basename[0] == '.';
}
