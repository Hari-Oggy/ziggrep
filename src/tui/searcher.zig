const std = @import("std");
const options = @import("../options.zig");
const SearchResults = @import("search_results.zig").SearchResults;
const SearchMatch = @import("search_results.zig").SearchMatch;
const regex = @import("regex");

const Options = options.Options;

const Match = struct {
    start: usize,
    end: usize,
};

pub fn searchFileToResults(
    allocator: std.mem.Allocator,
    filepath: []const u8,
    pattern: []const u8,
    opts: Options,
    results: *SearchResults,
) !void {
    var file = std.fs.cwd().openFile(filepath, .{}) catch {
        // Skip files we can't open
        return;
    };
    defer file.close();

    var file_buf: [4096]u8 = undefined;
    var buf_reader = file.reader(&file_buf);

    var line_buf: [4096]u8 = undefined;
    var line_len: usize = 0;
    var line_num: usize = 1;

    while (true) {
        const byte = buf_reader.interface.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if (line_len >= line_buf.len) {
            return error.LineTooLong;
        }

        line_buf[line_len] = byte;
        line_len += 1;

        if (byte == '\n') {
            const line = line_buf[0..line_len];

            // Binary check
            const is_binary = std.mem.indexOfScalar(u8, line, 0) != null;
            if (is_binary) {
                line_len = 0;
                line_num += 1;
                continue;
            }

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

            const raw_match = match_opt != null;
            const is_match = if (opts.invert_match) !raw_match else raw_match;

            if (is_match) {
                const highlight_match = if (opts.invert_match) null else match_opt;

                const search_match = SearchMatch{
                    .filepath = try allocator.dupe(u8, filepath),
                    .line_num = line_num,
                    .line_content = try allocator.dupe(u8, line),
                    .match_start = if (highlight_match) |m| m.start else 0,
                    .match_end = if (highlight_match) |m| m.end else 0,
                };

                try results.addMatch(search_match);
            }

            line_num += 1;
            line_len = 0;
        }
    }
}

fn matchesRegex(line: []const u8, pattern: []const u8, ignore_case: bool) !?Match {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var re = regex.Regex.compile(allocator, pattern) catch {
        return null;
    };
    defer re.deinit();

    _ = ignore_case;

    if (re.captures(line)) |caps_opt| {
        if (caps_opt) |caps| {
            if (caps.sliceAt(0)) |slice| {
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
