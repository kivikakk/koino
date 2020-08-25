const CMARK_CTYPE_CLASS: [256]u8 = [256]u8{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2,
    2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 2, 2, 2, 2, 2,
    2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 2, 2, 2, 2, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

pub fn isspace(ch: u8) bool {
    return CMARK_CTYPE_CLASS[ch] == 1;
}

pub fn ispunct(ch: u8) bool {
    return CMARK_CTYPE_CLASS[ch] == 2;
}

pub fn isdigit(ch: u8) bool {
    return CMARK_CTYPE_CLASS[ch] == 3;
}

pub fn isalpha(ch: u8) bool {
    return CMARK_CTYPE_CLASS[ch] == 4;
}

pub fn isalnum(ch: u8) bool {
    return CMARK_CTYPE_CLASS[ch] == 3 or CMARK_CTYPE_CLASS[ch] == 4;
}

pub fn isxdigit(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

const std = @import("std");

fn testEquivalence(name: []const u8, ours: fn (u8) bool, theirs: fn (u8) bool) void {
    var i: u8 = 0;
    while (true) : (i += 1) {
        std.testing.expectEqual(ours(i), theirs(i));
        if (i == 255) break;
    }
}

test "cmark ctype vs std.ascii" {
    testEquivalence("isspace", isspace, std.ascii.isSpace);
    testEquivalence("ispunct", ispunct, std.ascii.isPunct);
    testEquivalence("isdigit", isdigit, std.ascii.isDigit);
    testEquivalence("isalpha", isalpha, std.ascii.isAlpha);
    testEquivalence("isalnum", isalnum, std.ascii.isAlNum);
    testEquivalence("isxdigit", isxdigit, std.ascii.isXDigit);
}
