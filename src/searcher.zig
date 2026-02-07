const std = @import("std");
const options = @import("options.zig");
const output = @import("output.zig");
const regex = @import("regex");

const Options = options.Options;

pub fn searchFile(
    allocator: std.mem.Allocator,
    filepath: []const u8,
    pattern: []const u8,
    opts: Options,
    show_filename: bool,
    mutex: ?*std.Thread.Mutex,
) !void {
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var file_buf: [4096]u8 = undefined;
    var buf_reader = file.reader(&file_buf);

    var line_buf: [4096]u8 = undefined;
    var line_len: usize = 0;
    var line_num: usize = 1;

    // Buffer for thread-safe output
    var output_buffer = std.array_list.Managed(u8).init(allocator);
    defer output_buffer.deinit();
    const writer = output_buffer.writer();

    var before_buffer = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (before_buffer.items) |item| allocator.free(item);
        before_buffer.deinit();
    }

    var after_countdown: usize = 0;
    var last_printed_line: usize = 0;
    var match_count: usize = 0;
    const has_context = opts.before_context > 0 or opts.after_context > 0;

    while (true) {
        const byte = buf_reader.interface.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if (line_len >= line_buf.len) {
            // std.debug.print("Error: Line too long\n", .{});
            return error.LineTooLong;
        }

        line_buf[line_len] = byte;
        line_len += 1;

        if (byte == '\n') {
            const line = line_buf[0..line_len];

            // Binary Check
            const is_binary = std.mem.indexOfScalar(u8, line, 0) != null;

            // Check match
            var match_opt: ?Match = null;
            if (opts.use_regex) {
                match_opt = try matchesRegex(line, pattern, opts.ignore_case);
            } else if (opts.ignore_case) {
                match_opt = matchesCaseInsensitive(line, pattern);
            } else {
                if (std.mem.indexOf(u8, line, pattern)) |start| {
                    match_opt = Match{ .start = start, .end = start + pattern.len };
                }
            }
            // Determine effective match status
            const raw_match = match_opt != null;
            const is_match = if (opts.invert_match) !raw_match else raw_match;

            // Context Logic
            if (is_match) {
                // If listing files, print and stop (prioritize over count)
                if (opts.files_with_matches) {
                    try output.writeColored(writer, filepath, .magenta, opts.use_color);
                    try writer.writeByte('\n');
                    line_len = 0; // Prevent reprocessing
                    break;
                }

                // If counting, just increment and continue
                if (opts.count) {
                    match_count += 1;
                    line_num += 1;
                    line_len = 0;
                    continue;
                }

                if (is_binary) {
                    try output.writeColored(writer, "Binary file ", .magenta, opts.use_color);
                    try output.writeColored(writer, filepath, .magenta, opts.use_color);
                    try output.writeColored(writer, " matches\n", .magenta, opts.use_color);
                    line_len = 0; // Prevent reprocessing after break
                    break; // Stop processing this file
                }

                // Separator check: if we skipped lines since last print
                // The gap is between last_printed_line and (current_line - len(before_buffer))
                if (has_context and last_printed_line > 0 and line_num > last_printed_line + 1 + before_buffer.items.len) {
                    try output.writeColored(writer, "--\n", .cyan, opts.use_color);
                }

                // Print buffered before-lines
                for (before_buffer.items, 0..) |item, i| {
                    const buf_line_num = line_num - before_buffer.items.len + i;
                    // For context lines, we use '-' separator instead of ':' ?
                    // Standard grep: ':' for matching lines, '-' for context lines.
                    try processLine(writer, item, opts, show_filename, filepath, buf_line_num, null); // Context
                    allocator.free(item);
                }
                before_buffer.clearRetainingCapacity();

                // Print current match line
                // If inverted match, match_opt is null (or whatever raw match was).
                // If invert_match is true, we want to print the line.
                // match_opt corresponds to what we want to highlight.
                // If invert_match, we highlight NOTHING?
                // Standard grep -v: no highlighting.
                // So pass null if invert_match.
                const highlight_match = if (opts.invert_match) null else match_opt;
                try processLine(writer, line, opts, show_filename, filepath, line_num, highlight_match);
                last_printed_line = line_num;
                after_countdown = opts.after_context;
            } else {
                // No match logic remains same (buffers context)
                // If checking count/list, we don't care about context?
                // Standard grep -c/-l implies no context.
                // If we are here, is_match is false.

                if (opts.count or opts.files_with_matches) {
                    // Do nothing
                } else {
                    if (after_countdown > 0) {
                        try processLine(writer, line, opts, show_filename, filepath, line_num, null); // Context (after)
                        last_printed_line = line_num;
                        after_countdown -= 1;
                    } else if (opts.before_context > 0) {
                        // Buffer this current line
                        if (before_buffer.items.len >= opts.before_context) {
                            const old = before_buffer.orderedRemove(0);
                            allocator.free(old);
                        }
                        try before_buffer.append(try allocator.dupe(u8, line));
                    }
                }
            }

            line_num += 1;
            line_len = 0;
        }
    }

    if (line_len > 0) {
        // Handle last line (no newline) logic same as above...
        // For simplicity, let's ignore context logic for partial last line for now or duplicate it.
        // Actually, partial line usually doesn't match? Or if it does?
        // Let's just process it simply.
        const line = line_buf[0..line_len];
        // Handle last line match check
        var match_opt: ?Match = null;
        if (opts.use_regex) {
            match_opt = try matchesRegex(line, pattern, opts.ignore_case);
        } else if (opts.ignore_case) {
            match_opt = matchesCaseInsensitive(line, pattern);
        } else {
            if (std.mem.indexOf(u8, line, pattern)) |start| {
                match_opt = Match{ .start = start, .end = start + pattern.len };
            }
        }
        try processLine(writer, line, opts, show_filename, filepath, line_num, match_opt);
    }

    if (opts.count and !opts.files_with_matches) {
        if (show_filename) {
            try output.writeColored(writer, filepath, .magenta, opts.use_color);
            try output.writeColored(writer, ":", .cyan, opts.use_color);
        }
        try writer.print("{d}\n", .{match_count});
    }

    // Write buffered output to stdout (thread-safe)
    if (output_buffer.items.len > 0) {
        if (mutex) |m| m.lock();
        defer if (mutex) |m| m.unlock();

        const stdout = std.fs.File.stdout();
        try stdout.writeAll(output_buffer.items);
    }
}

const Match = struct {
    start: usize,
    end: usize,
};

fn processLine(
    writer: anytype,
    line: []const u8,
    opts: Options,
    show_filename: bool,
    filepath: []const u8,
    line_num: usize,
    match_opt: ?Match,
) !void {
    // Only print if it's a match OR we are called (which implies it's a context line)
    // Wait, processLine is called explicitly for context lines too.
    // So we ALWAYS print.

    // Separator between filename/linenum and content:
    // grep uses ':' for matching lines, '-' for context lines.
    const separator: u8 = if (match_opt != null) ':' else '-';

    if (show_filename) {
        try output.writeColored(writer, filepath, .magenta, opts.use_color);
        try writer.writeByte(separator);
    }

    if (opts.show_line_numbers) {
        var num_buf: [20]u8 = undefined;
        const num_str = try std.fmt.bufPrint(&num_buf, "{d}", .{line_num});
        try output.writeColored(writer, num_str, .green, opts.use_color);
        try writer.writeByte(separator);
    }

    if (match_opt) |match| {
        // Highlight match
        if (opts.use_color) {
            try writer.writeAll(line[0..match.start]);
            try output.writeColored(writer, line[match.start..match.end], .red, true);
            try writer.writeAll(line[match.end..]);
        } else {
            try writer.writeAll(line);
        }
    } else {
        try writer.writeAll(line);
    }

    if (line.len == 0 or line[line.len - 1] != '\n') {
        try writer.writeByte('\n');
    }
}

fn matchesRegex(line: []const u8, pattern: []const u8, ignore_case: bool) !?Match {
    // Create a temporary allocator for regex compilation
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Compile the regex pattern
    var re = regex.Regex.compile(allocator, pattern) catch {
        // std.debug.print("Invalid regex pattern '{s}': {}\n", .{ pattern, err });
        return null; // Treat invalid regex as no match
    };
    defer re.deinit();

    // Apply case-insensitive flag if needed
    if (ignore_case) {
        // Note: zig-regex might not support case-insensitive flag directly
        // We'll try to match as-is for now
    }

    // Capture the match to get indices using 'captures' API
    // captures returns !?Captures.
    if (re.captures(line)) |caps_opt| {
        if (caps_opt) |caps| {
            // Slice 0 is the full match
            if (caps.sliceAt(0)) |slice| {
                // Calculate offsets using pointer arithmetic
                const start = @intFromPtr(slice.ptr) - @intFromPtr(line.ptr);
                const end = start + slice.len;

                return Match{ .start = start, .end = end };
            }
        }
    } else |_| {
        return null;
    }

    return null;
}

fn matchesCaseInsensitive(line: []const u8, pattern: []const u8) ?Match {
    var i: usize = 0;
    while (i + pattern.len <= line.len) : (i += 1) {
        var match = true;
        for (pattern, 0..) |p_char, j| {
            const l_char = line[i + j];
            if (std.ascii.toLower(p_char) != std.ascii.toLower(l_char)) {
                match = false;
                break;
            }
        }
        if (match) return Match{ .start = i, .end = i + pattern.len };
    }
    return null;
}
