const std = @import("std");
const vaxis = @import("vaxis");
const options = @import("../options.zig");
const SearchResults = @import("search_results.zig").SearchResults;

pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub const App = struct {
    const List = std.ArrayList(u8);

    allocator: std.mem.Allocator,
    should_quit: bool = false,

    // UI State
    query_buf: List = .{},
    cursor_idx: usize = 0,

    // Search State
    search_results: SearchResults,
    selected_idx: usize = 0,
    current_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !App {
        const cwd = try std.process.getCwdAlloc(allocator);
        return .{
            .allocator = allocator,
            .search_results = SearchResults.init(allocator),
            .current_dir = cwd,
        };
    }

    pub fn deinit(self: *App) void {
        self.query_buf.deinit(self.allocator);
        self.search_results.deinit();
        self.allocator.free(self.current_dir);
    }

    pub fn update(self: *App, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                    self.should_quit = true;
                    return;
                }

                if (key.text) |text| {
                    try self.query_buf.insertSlice(self.allocator, self.cursor_idx, text);
                    self.cursor_idx += text.len;
                } else {
                    switch (key.codepoint) {
                        vaxis.Key.backspace => {
                            if (self.cursor_idx > 0) {
                                self.cursor_idx -= 1;
                                _ = self.query_buf.orderedRemove(self.cursor_idx);
                            }
                        },
                        vaxis.Key.left => {
                            if (self.cursor_idx > 0) self.cursor_idx -= 1;
                        },
                        vaxis.Key.right => {
                            if (self.cursor_idx < self.query_buf.items.len) self.cursor_idx += 1;
                        },
                        vaxis.Key.up => {
                            if (self.selected_idx > 0) self.selected_idx -= 1;
                        },
                        vaxis.Key.down => {
                            if (self.selected_idx + 1 < self.search_results.matches.items.len) {
                                self.selected_idx += 1;
                            }
                        },
                        vaxis.Key.enter => {
                            try self.triggerSearch();
                        },
                        else => {},
                    }
                }
            },
            .winsize => {},
        }
    }

    fn triggerSearch(self: *App) !void {
        if (self.query_buf.items.len == 0) return;

        self.search_results.clear();
        self.search_results.is_searching = true;
        self.selected_idx = 0;

        const pattern = self.query_buf.items;

        // Create search options
        const opts = options.Options{
            .show_line_numbers = true,
            .ignore_case = false,
            .recursive = true,
            .use_regex = false,
            .use_color = false,
            .count = false,
            .files_with_matches = false,
            .invert_match = false,
            .hidden = false,
            .include_types = &[_][]const u8{},
            .exclude_types = &[_][]const u8{},
            .globs = &[_][]const u8{},
            .before_context = 0,
            .after_context = 0,
        };

        // Search current directory using simple file iteration
        const searcher = @import("searcher.zig");

        var dir = try std.fs.cwd().openDir(self.current_dir, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            // Build full path
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const filepath = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.current_dir, entry.name });

            searcher.searchFileToResults(
                self.allocator,
                filepath,
                pattern,
                opts,
                &self.search_results,
            ) catch continue;

            // Limit results to prevent UI slowdown
            if (self.search_results.matches.items.len >= 100) {
                break;
            }
        }

        self.search_results.is_searching = false;
    }

    pub fn draw(self: *App, win: vaxis.Window) !void {
        win.clear();

        // Title
        _ = win.printSegment(.{
            .text = "ZigGrep TUI - Interactive Search",
        }, .{ .row_offset = 0, .col_offset = 2 });

        // Input box with label
        _ = win.printSegment(.{
            .text = "Search:",
        }, .{ .row_offset = 2, .col_offset = 2 });

        const input_box = win.child(.{
            .x_off = 11,
            .y_off = 2,
            .width = if (win.width > 15) win.width - 15 else 20,
            .height = 1,
        });

        _ = input_box.printSegment(.{
            .text = self.query_buf.items,
        }, .{});
        input_box.showCursor(@intCast(self.cursor_idx), 0);

        // Separator
        _ = win.printSegment(.{
            .text = "─────────────────────────────────────────────────",
        }, .{ .row_offset = 4, .col_offset = 0 });

        // Results area
        const results_start: u16 = 6;

        if (self.search_results.is_searching) {
            _ = win.printSegment(.{
                .text = "Searching...",
            }, .{ .row_offset = results_start, .col_offset = 2 });
        } else if (self.search_results.error_msg) |err| {
            _ = win.printSegment(.{
                .text = "Error: ",
            }, .{ .row_offset = results_start, .col_offset = 2 });
            _ = win.printSegment(.{
                .text = err,
            }, .{ .row_offset = results_start, .col_offset = 9 });
        } else if (self.search_results.matches.items.len > 0) {
            // Draw results
            var row: u16 = results_start;
            const max_results: usize = @min(self.search_results.matches.items.len, 20);

            for (self.search_results.matches.items[0..max_results], 0..) |match, i| {
                if (row >= win.height - 3) break;

                const is_selected = i == self.selected_idx;
                const prefix = if (is_selected) "> " else "  ";

                var buf: [256]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "{s}{s}:{d}", .{
                    prefix,
                    match.filepath,
                    match.line_num,
                }) catch continue;

                _ = win.printSegment(.{
                    .text = line,
                }, .{ .row_offset = row, .col_offset = 0 });

                row += 1;
            }
        } else if (self.query_buf.items.len > 0) {
            _ = win.printSegment(.{
                .text = "No results found",
            }, .{ .row_offset = results_start, .col_offset = 2 });
        }

        // Status bar at bottom
        if (win.height > 2) {
            const status_y = win.height - 2;

            // Separator
            _ = win.printSegment(.{
                .text = "─────────────────────────────────────────────────",
            }, .{ .row_offset = status_y - 1, .col_offset = 0 });

            var status_buf: [128]u8 = undefined;
            const status = std.fmt.bufPrint(&status_buf, "Results: {d} | Enter=search ↑↓=navigate q=quit", .{
                self.search_results.matches.items.len,
            }) catch "Status";

            _ = win.printSegment(.{
                .text = status,
            }, .{ .row_offset = status_y, .col_offset = 2 });
        }
    }
};
