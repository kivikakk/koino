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
