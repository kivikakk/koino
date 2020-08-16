const std = @import("std");
const mem = std.mem;
const testing = std.testing;
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

test "isBlank" {
    testing.expect(isBlank(""));
    testing.expect(isBlank("\nx"));
    testing.expect(isBlank("    \t\t  \r"));
    testing.expect(!isBlank("e"));
    testing.expect(!isBlank("   \t    e "));
}

pub fn rtrim(s: []const u8) []const u8 {
    var len = s.len;
    while (len > 0 and ctype.isspace(s[len - 1])) {
        len -= 1;
    }
    return s[0..len];
}

test "rtrim" {
    testing.expectEqualStrings("abc", rtrim("abc"));
    testing.expectEqualStrings("abc", rtrim("abc   "));
    testing.expectEqualStrings("abc", rtrim("abc      \n\n \t\r "));
    testing.expectEqualStrings("  \nabc \n zz", rtrim("  \nabc \n zz \n"));
}

pub fn chopTrailingHashtags(s: []const u8) []const u8 {
    var r = rtrim(s);
    if (r.len == 0) return r;

    const orig_n = r.len - 1;
    var n = orig_n;
    while (r[n] == '#') : (n -= 1) {
        if (n == 0) return r;
    }

    if (n != orig_n and isSpaceOrTab(r[n])) {
        return rtrim(r[0..n]);
    } else {
        return r;
    }
}

test "chopTrailingHashtags" {
    testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz"));
    testing.expectEqualStrings("xyz#", chopTrailingHashtags("xyz#"));
    testing.expectEqualStrings("xyz###", chopTrailingHashtags("xyz###"));
    testing.expectEqualStrings("xyz###", chopTrailingHashtags("xyz###  "));
    testing.expectEqualStrings("xyz###", chopTrailingHashtags("xyz###  #"));
    testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz  "));
    testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz  ##"));
    testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz  ##"));
}

pub fn normalizeCode(allocator: *mem.Allocator, s: []const u8) ![]u8 {
    var code = std.ArrayList(u8).init(allocator);

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

    return code.toOwnedSlice();
}

test "normalizeCode" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    var alloc = &arena.allocator;

    testing.expectEqualStrings("qwe", try normalizeCode(alloc, "qwe"));
    testing.expectEqualStrings("qwe", try normalizeCode(alloc, " qwe "));
    testing.expectEqualStrings("qwe", try normalizeCode(alloc, " qwe "));
    testing.expectEqualStrings("abc def' def", try normalizeCode(alloc, " abc\rdef'\r\ndef "));
}
