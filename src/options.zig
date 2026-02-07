const std = @import("std");

pub const Options = struct {
    show_line_numbers: bool = false,
    ignore_case: bool = false,
    use_color: bool = false,
    recursive: bool = false,
    use_regex: bool = false,
    before_context: usize = 0,
    after_context: usize = 0,
    count: bool = false,
    files_with_matches: bool = false,
    invert_match: bool = false,
    hidden: bool = false,
    include_types: []const []const u8 = &.{},
    exclude_types: []const []const u8 = &.{},
    globs: []const []const u8 = &.{},
};

pub const Args = struct {
    options: Options,
    pattern: []const u8,
    paths: [][]const u8,
};

pub fn parseArgs(allocator: std.mem.Allocator) !Args {
    const all_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, all_args);

    var options = Options{};
    var pattern: ?[]const u8 = null;
    var paths = std.ArrayList([]const u8).empty;
    defer paths.deinit(allocator);

    var include_types = std.ArrayList([]const u8).empty;
    // defer include_types.deinit(allocator); // We transfer ownership
    errdefer include_types.deinit(allocator);

    var exclude_types = std.ArrayList([]const u8).empty;
    errdefer exclude_types.deinit(allocator);

    var globs = std.ArrayList([]const u8).empty;
    errdefer globs.deinit(allocator);

    var i: usize = 1;
    while (i < all_args.len) : (i += 1) {
        const arg = all_args[i];
        if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--line-number")) {
            options.show_line_numbers = true;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore-case")) {
            options.ignore_case = true;
        } else if (std.mem.eql(u8, arg, "--color")) {
            options.use_color = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--recursive")) {
            options.recursive = true;
        } else if (std.mem.eql(u8, arg, "-E") or std.mem.eql(u8, arg, "--regex")) {
            options.use_regex = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--count")) {
            options.count = true;
        } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--files-with-matches")) {
            options.files_with_matches = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--invert-match")) {
            options.invert_match = true;
        } else if (std.mem.eql(u8, arg, "--hidden")) {
            options.hidden = true;
        } else if (std.mem.eql(u8, arg, "-A") or std.mem.eql(u8, arg, "--after-context")) {
            i += 1;
            if (i >= all_args.len) return error.InvalidArgs;
            options.after_context = std.fmt.parseInt(usize, all_args[i], 10) catch return error.InvalidArgs;
        } else if (std.mem.eql(u8, arg, "-B") or std.mem.eql(u8, arg, "--before-context")) {
            i += 1;
            if (i >= all_args.len) return error.InvalidArgs;
            options.before_context = std.fmt.parseInt(usize, all_args[i], 10) catch return error.InvalidArgs;
        } else if (std.mem.eql(u8, arg, "-C") or std.mem.eql(u8, arg, "--context")) {
            i += 1;
            if (i >= all_args.len) return error.InvalidArgs;
            const val = std.fmt.parseInt(usize, all_args[i], 10) catch return error.InvalidArgs;
            options.before_context = val;
            options.after_context = val;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--type")) {
            i += 1;
            if (i >= all_args.len) return error.InvalidArgs;
            try include_types.append(allocator, try allocator.dupe(u8, all_args[i]));
        } else if (std.mem.eql(u8, arg, "-T") or std.mem.eql(u8, arg, "--type-not")) {
            i += 1;
            if (i >= all_args.len) return error.InvalidArgs;
            try exclude_types.append(allocator, try allocator.dupe(u8, all_args[i]));
        } else if (std.mem.eql(u8, arg, "-g") or std.mem.eql(u8, arg, "--glob")) {
            i += 1;
            if (i >= all_args.len) return error.InvalidArgs;
            try globs.append(allocator, try allocator.dupe(u8, all_args[i]));
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return error.HelpRequested;
        } else if (pattern == null) {
            // Duplicate the pattern string so it remains valid after argsFree
            pattern = try allocator.dupe(u8, arg);
        } else {
            // Duplicate path strings so they remain valid after argsFree
            try paths.append(allocator, try allocator.dupe(u8, arg));
        }
    }

    if (pattern == null or paths.items.len == 0) {
        printHelp();
        return error.InvalidArgs;
    }

    return Args{
        .options = .{
            .show_line_numbers = options.show_line_numbers,
            .ignore_case = options.ignore_case,
            .use_color = options.use_color,
            .recursive = options.recursive,
            .use_regex = options.use_regex,
            .before_context = options.before_context,
            .after_context = options.after_context,
            .count = options.count,
            .files_with_matches = options.files_with_matches,
            .invert_match = options.invert_match,
            .hidden = options.hidden,
            .include_types = try include_types.toOwnedSlice(allocator),
            .exclude_types = try exclude_types.toOwnedSlice(allocator),
            .globs = try globs.toOwnedSlice(allocator),
        },
        .pattern = pattern.?,
        .paths = try paths.toOwnedSlice(allocator),
    };
}

pub fn printHelp() void {
    std.debug.print(
        \\Usage: ziggrep [OPTIONS] PATTERN PATH...
        \\
        \\Search for PATTERN in files.
        \\
        \\Options:
        \\  -n, --line-number    Show line numbers
        \\  -i, --ignore-case    Case-insensitive search
        \\  -r, --recursive      Search directories recursively
        \\  -E, --regex          Use regex patterns
        \\  -c, --count          Print only a count of selected lines
        \\  -l, --files-with-matches  Print only names of files containing matches
        \\  -v, --invert-match   Select non-matching lines
        \\  --hidden             Search hidden files and directories
        \\  -t, --type TYPE      Include files matching TYPE (e.g. c, zig)
        \\  -T, --type-not TYPE  Exclude files matching TYPE
        \\  -g, --glob GLOB      Include files matching ignoring case GLOB
        \\  -A, --after-context  Print N lines after match
        \\  -B, --before-context Print N lines before match
        \\  -C, --context        Print N lines around match
        \\  --color              Force colored output
        \\  -h, --help           Show this help message
        \\
        \\Examples:
        \\  ziggrep "error" log.txt
        \\  ziggrep -n "TODO" src/main.zig
        \\  ziggrep -r "std" ./src/
        \\  ziggrep -E "fn \w+\(" ./src/
        \\
    , .{});
}
