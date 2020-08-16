const std = @import("std");
const ctregex = @import("ctregex");

fn search(line: []const u8, matched: *usize, comptime regex: []const u8) !bool {
    if (try ctregex.match(regex, .{ .complete = false }, line)) |res| {
        matched.* = res.slice.len;
        return true;
    }
    return false;
}

fn match(line: []const u8, comptime regex: []const u8) !bool {
    if (try ctregex.match(regex, .{}, line)) |res| {
        return true;
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
    return try search(line, matched, "#{1,6}[\\ \\\t\r\n]");
}

pub fn thematicBreak(line: []const u8, matched: *usize) !bool {
    @setEvalBranchQuota(3000);
    if (line[0] != '*' and line[0] != '-' and line[0] != '_') {
        return false;
    }
    return try search(line, matched, "((\\*[\\ \\\t]*){3,}|(_[\\ \\\t]*){3,}|(-[\\ \\\t]*){3,})[\\ \\\t]*[\r\n]");
}

test "thematicBreak" {
    var matched: usize = undefined;
    std.testing.expect(!try thematicBreak("hello", &matched));
    std.testing.expect(try thematicBreak("***\n", &matched));
    std.testing.expectEqual(@as(usize, 4), matched);
    std.testing.expect(try thematicBreak("-          -   -    \r", &matched));
    std.testing.expectEqual(@as(usize, 21), matched);
    std.testing.expect(try thematicBreak("-          -   -    \r\nxyz", &matched));
    std.testing.expectEqual(@as(usize, 21), matched);
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
