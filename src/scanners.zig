const std = @import("std");
const testing = std.testing;
const Regex = @import("zig-regex").Regex;

fn search(line: []const u8, matched: *usize, regex: []const u8) !bool {
    var re = try Regex.compile(testing.allocator, regex);
    defer re.deinit();
    if (try re.captures(line)) |captures| {
        if (captures.boundsAt(0).?.lower == 0) {
            matched.* = captures.boundsAt(0).?.upper;
            return true;
        }
    }
    return false;
}

fn match(line: []const u8, comptime regex: []const u8) !bool {
    var re = try Regex.compile(testing.allocator, regex);
    defer re.deinit();
    if (try re.captures(line)) |captures| {
        if (captures.boundsAt(0).?.lower == 0 and captures.boundsAt(0).?.upper == line.len) {
            return true;
        }
    }
    return false;
}

pub fn htmlBlockEnd1(line: []const u8) bool {
    unreachable;
}

pub fn htmlBlockEnd2(line: []const u8) bool {
    unreachable;
}

pub fn htmlBlockEnd3(line: []const u8) bool {
    unreachable;
}

pub fn htmlBlockEnd4(line: []const u8) bool {
    unreachable;
}

pub fn htmlBlockEnd5(line: []const u8) bool {
    unreachable;
}

pub fn closeCodeFence(line: []const u8) ?usize {
    unreachable;
}

pub fn atxHeadingStart(line: []const u8, matched: *usize) !bool {
    if (line[0] != '#') {
        return false;
    }
    return try search(line, matched, "#{1,6}[ \t\r\n]");
}

pub fn thematicBreak(line: []const u8, matched: *usize) !bool {
    if (line[0] == '*') {
        return try search(line, matched, "(\\*[ \t]*){3,}[ \t]*[\r\n]");
    } else if (line[0] == '_') {
        return try search(line, matched, "(_[ \t]*){3,}[ \t]*[\r\n]");
    } else if (line[0] == '-') {
        return try search(line, matched, "(-[ \t]*){3,}[ \t]*[\r\n]");
    }
    return false;
}

test "thematicBreak" {
    var matched: usize = undefined;
    testing.expect(!try thematicBreak("hello", &matched));
    testing.expect(try thematicBreak("***\n", &matched));
    testing.expectEqual(@as(usize, 4), matched);
    testing.expect(try thematicBreak("-          -   -    \r", &matched));
    testing.expectEqual(@as(usize, 21), matched);
    testing.expect(try thematicBreak("-          -   -    \r\nxyz", &matched));
    testing.expectEqual(@as(usize, 21), matched);
}

pub const SetextChar = enum {
    Equals,
    Hyphen,
};

pub fn setextHeadingLine(line: []const u8, sc: *SetextChar) !bool {
    if ((line[0] == '=' or line[0] == '-') and try match(line, "(=+|-+)[\\ \\\t]*[\r\n]")) {
        sc.* = if (line[0] == '=') .Equals else .Hyphen;
        return true;
    }
    return false;
}

const scheme = "[A-Za-z][A-Za-z0-9.+\\-]{1,31}";

pub fn autolinkUri(line: []const u8, matched: *usize) !bool {
    @setEvalBranchQuota(2000);
    // TODO: deal with unicode weirdness here instead of `catch false'

    // XXX: working around ctregex weirdness here: "\x00-\x20" is expressed as "\x00-\\ \x20"
    // because \x20 is in fact 'SPACE' (U+0020), and ctregex skips those (and 'CHARACTER
    // TABULATION' U+0009).
    return search(line, matched, scheme ++ ":[^\x00-\\ \x20<>]*" ++ ">") catch false;
}

test "autolinkUri" {
    var matched: usize = undefined;
    testing.expect(!try autolinkUri("www.google.com>", &matched));
    testing.expect(try autolinkUri("https://www.google.com>", &matched));
    testing.expectEqual(@as(usize, 23), matched);
    testing.expect(try autolinkUri("a+b-c:>", &matched));
    testing.expectEqual(@as(usize, 7), matched);
    testing.expect(!try autolinkUri("a+b-c:", &matched));
}

pub fn autolinkEmail(line: []const u8, matched: *usize) !bool {
    @setEvalBranchQuota(5000);
    const user_part = "[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~\\-]+";
    const host_part = "[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?";
    const rest = "(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*";
    const re = user_part ++ "@" ++ host_part ++ rest ++ ">";
    // TODO: as above
    var r = search(line, matched, re);
    std.debug.warn("{} ~ {}\n", .{ re, r });
    return r catch false;
}

test "autolinkEmail" {
    var matched: usize = undefined;
    testing.expect(!try autolinkEmail("abc>", &matched));
    testing.expect(!try autolinkEmail("abc.def>", &matched));
    testing.expect(!try autolinkEmail("abc@def", &matched));
    //testing.expect(try autolinkEmail("abc@def>", &matched));
    //testing.expectEqual(@as(usize, 8), matched);
    testing.expect(try autolinkEmail("abc+123!?@96--1>", &matched));
    testing.expectEqual(@as(usize, 7), matched);
}
