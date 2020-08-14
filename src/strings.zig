const std = @import("std");
const ctype = @import("ctype.zig");

pub fn isLineEndChar(ch: u8) bool {
    return switch (ch) {
        '\n', '\r' => true,
        else => false,
    };
}

pub fn isSpaceOrTab(ch: u8) bool {
    return switch (ch) {
        ' ', '\t' => true,
        else => false,
    };
}

pub fn isBlank(s: []const u8) bool {
    for (s) |c| {
        switch (c) {
            '\n', '\r' => return true,
            ' ', '\t' => {},
            else => return false,
        }
    }
    return true;
}

pub fn rtrim(s: []const u8) []const u8 {
    var len = s.len;
    while (len > 0 and ctype.isspace(s[len - 1])) {
        len -= 1;
    }
    return s[0..len];
}

pub fn normalizeCode(s: []const u8, code: *std.ArrayList(u8)) !void {
    var i: usize = 0;
    var contains_nonspace = false;

    while (i < s.len) {
        switch (s[i]) {
            '\r' => {
                if (i + 1 == s.len or s[i + 1] != '\n') {
                    try code.append(' ');
                }
            },
            '\n' => {
                try code.append(' ');
            },
            else => try code.append(s[i]),
        }
        if (s[i] != ' ') {
            contains_nonspace = true;
        }
        i += 1;
    }

    if (contains_nonspace and code.items.len != 0 and code.span()[0] == ' ' and code.span()[code.items.len - 1] == ' ') {
        _ = code.orderedRemove(0);
        _ = code.pop();
    }
}
