const std = @import("std");
const regex = @import("regex");
const glob = @import("glob.zig");

pub const IgnoreRule = struct {
    pattern: regex.Regex,
    negative: bool, // True if pattern starts with !
    directory_only: bool, // True if pattern ends with /
    match_basename: bool, // True if pattern has no slash
};

pub fn parseIgnoreFile(allocator: std.mem.Allocator, dir_path: []const u8) ![]IgnoreRule {
    const gitignore_path = try std.fs.path.join(allocator, &.{ dir_path, ".gitignore" });
    defer allocator.free(gitignore_path);

    var file = std.fs.cwd().openFile(gitignore_path, .{}) catch |err| {
        if (err == error.FileNotFound) return &.{};
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB limit for gitignore
    defer allocator.free(content);

    var lines = std.mem.tokenizeScalar(u8, content, '\n');

    var rules = std.ArrayList(IgnoreRule).empty;
    errdefer {
        for (rules.items) |*r| r.pattern.deinit();
        rules.deinit(allocator);
    }

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        var pattern = trimmed;
        var negative = false;
        if (pattern[0] == '!') {
            negative = true;
            pattern = pattern[1..];
        }

        var directory_only = false;
        if (pattern.len > 0 and pattern[pattern.len - 1] == '/') {
            directory_only = true;
            pattern = pattern[0 .. pattern.len - 1];
        }

        const match_basename = std.mem.indexOfScalar(u8, pattern, '/') == null;

        // Convert glob to regex
        // We use our globToRegex info.
        // For gitignore, strict globbing is needed.
        // Also handling leading slash logic (implicitly handled by our globToRegex?)
        // If pattern has no slash (except trailing), it matches anywhere.
        // If pattern has slash, it is anchored to .gitignore location.
        // Currently globToRegex returns ^...$ regex.
        // To support "match anywhere", we might need to prepend "(.*/)?".

        // This is complex. For this MVP, let's treat all patterns as "match basename or relative path".
        // Improved globbing in glob.zig handles * and **.

        const regex_str = try glob.globToRegex(allocator, pattern);
        defer allocator.free(regex_str);

        const re = regex.Regex.compile(allocator, regex_str) catch {
            continue; // Skip invalid patterns
        };

        try rules.append(allocator, .{
            .pattern = re,
            .negative = negative,
            .directory_only = directory_only,
            .match_basename = match_basename,
        });
    }

    return rules.toOwnedSlice(allocator);
}
