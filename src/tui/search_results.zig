const std = @import("std");

pub const SearchMatch = struct {
    filepath: []const u8,
    line_num: usize,
    line_content: []const u8,
    match_start: usize,
    match_end: usize,

    pub fn deinit(self: SearchMatch, allocator: std.mem.Allocator) void {
        allocator.free(self.filepath);
        allocator.free(self.line_content);
    }
};

pub const SearchResults = struct {
    allocator: std.mem.Allocator,
    matches: std.ArrayList(SearchMatch) = .{},
    is_searching: bool = false,
    error_msg: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) SearchResults {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SearchResults) void {
        for (self.matches.items) |match| {
            match.deinit(self.allocator);
        }
        self.matches.deinit(self.allocator);
        if (self.error_msg) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn clear(self: *SearchResults) void {
        for (self.matches.items) |match| {
            match.deinit(self.allocator);
        }
        self.matches.clearRetainingCapacity();
        if (self.error_msg) |msg| {
            self.allocator.free(msg);
            self.error_msg = null;
        }
    }

    pub fn addMatch(self: *SearchResults, match: SearchMatch) !void {
        try self.matches.append(self.allocator, match);
    }

    pub fn setError(self: *SearchResults, msg: []const u8) !void {
        if (self.error_msg) |old| {
            self.allocator.free(old);
        }
        self.error_msg = try self.allocator.dupe(u8, msg);
    }
};
