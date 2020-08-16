const std = @import("std");
const ctregex = @import("ctregex");

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

    if (try ctregex.match("#{1,6}[\\ \\\t\r\n]", .{ .complete = false }, line)) |res| {
        matched.* = res.slice.len;
        return true;
    }
    return false;
}
