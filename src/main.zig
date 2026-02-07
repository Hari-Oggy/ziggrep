const std = @import("std");
const options = @import("options.zig");
const searcher = @import("searcher.zig");
const walker = @import("walker.zig");
const output = @import("output.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = options.parseArgs(allocator) catch |err| {
        if (err == error.HelpRequested or err == error.InvalidArgs) {
            return;
        }
        return err;
    };
    defer {
        // Free each path string
        for (args.paths) |path| {
            allocator.free(path);
        }
        // Free the paths array
        allocator.free(args.paths);
        // Free the pattern
        allocator.free(args.pattern);
    }

    // Auto-detect color if not explicitly set
    var opts = args.options;
    if (!opts.use_color) {
        opts.use_color = output.isTty();
    }

    const show_filename = args.paths.len > 1 or opts.recursive;

    // Initialize thread pool and mutex
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var mutex = std.Thread.Mutex{};

    // Check for TUI mode
    if (opts.tui) {
        const tui = @import("tui/main.zig");
        try tui.run(allocator, args);
        return;
    }

    for (args.paths) |path| {
        processPath(allocator, path, args.pattern, opts, show_filename, &pool, &mutex) catch |err| {
            std.debug.print("Error processing '{s}': {}\n", .{ path, err });
        };
    }
}

fn processPath(
    allocator: std.mem.Allocator,
    path: []const u8,
    pattern: []const u8,
    opts: options.Options,
    show_filename: bool,
    pool: *std.Thread.Pool,
    mutex: *std.Thread.Mutex,
) !void {
    const stat = std.fs.cwd().statFile(path) catch |err| {
        if (err == error.FileNotFound) {
            // Try as directory - actually statFile works on directories too
            // If it's not found, it's not found.
        }
        return err;
    };

    if (stat.kind == .directory) {
        if (opts.recursive) {
            return processDirectory(allocator, path, pattern, opts, show_filename, pool, mutex);
        } else {
            std.debug.print("'{s}' is a directory (use -r for recursive search)\n", .{path});
            return;
        }
    } else {
        // Spawn worker for single file
        // We must duplicate path because worker frees it
        const path_copy = try allocator.dupe(u8, path);
        try pool.spawn(worker, .{ allocator, path_copy, pattern, opts, show_filename, mutex });
    }
}

fn processDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    pattern: []const u8,
    opts: options.Options,
    show_filename: bool,
    pool: *std.Thread.Pool,
    mutex: *std.Thread.Mutex,
) !void {
    // Context to pass data to walker callback
    const SearchContext = struct {
        var current_pattern: []const u8 = undefined;
        var current_opts: options.Options = undefined;
        var current_show_filename: bool = undefined;
        var current_allocator: std.mem.Allocator = undefined;
        var current_pool: *std.Thread.Pool = undefined;
        var current_mutex: *std.Thread.Mutex = undefined;

        fn callback(filepath: []const u8) !void {
            // Duplicate path (walker owns the original)
            const path_copy = try current_allocator.dupe(u8, filepath);
            try current_pool.spawn(worker, .{ current_allocator, path_copy, current_pattern, current_opts, current_show_filename, current_mutex });
        }
    };

    SearchContext.current_pattern = pattern;
    SearchContext.current_opts = opts;
    SearchContext.current_show_filename = show_filename;
    SearchContext.current_allocator = allocator;
    SearchContext.current_pool = pool;
    SearchContext.current_mutex = mutex;

    try walker.walkDirectory(allocator, dir_path, opts, &SearchContext.callback);
}

fn worker(
    allocator: std.mem.Allocator,
    path: []const u8,
    pattern: []const u8,
    opts: options.Options,
    show_filename: bool,
    mutex: *std.Thread.Mutex,
) void {
    defer allocator.free(path);
    searcher.searchFile(allocator, path, pattern, opts, show_filename, mutex) catch {};
}
