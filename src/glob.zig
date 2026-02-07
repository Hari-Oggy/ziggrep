const std = @import("std");

pub fn globToRegex(allocator: std.mem.Allocator, glob: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try buf.append(allocator, '^');

    // Handle leading slash (anchor to root)

    var i: usize = 0;
    while (i < glob.len) : (i += 1) {
        const c = glob[i];
        switch (c) {
            '*' => {
                // Check if double star **
                if (i + 1 < glob.len and glob[i + 1] == '*') {
                    // ** matches any directories
                    try buf.appendSlice(allocator, ".*");
                    i += 1;
                } else {
                    // * matches anything EXCEPT path separator
                    try buf.appendSlice(allocator, "[^/]*");
                }
            },
            '?' => try buf.appendSlice(allocator, "[^/]"),
            '.' => try buf.appendSlice(allocator, "\\."),
            '/' => try buf.append(allocator, '/'),
            '{', '}', '(', ')', '+', '|', '^', '$', '[', ']', '\\' => {
                try buf.append(allocator, '\\');
                try buf.append(allocator, c);
            },
            else => try buf.append(allocator, c),
        }
    }

    try buf.append(allocator, '$');
    return buf.toOwnedSlice(allocator);
}
