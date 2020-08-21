const std = @import("std");
const testing = std.testing;
const Regex = @import("libpcre").Regex;

const Error = error{OutOfMemory};

// TODO: compile once.
fn search(line: []const u8, matched: *usize, regex: [:0]const u8) Error!bool {
    var re = Regex.compile(regex, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer re.deinit();
    if (re.matches(line, .{ .Anchored = true }) catch null) |cap| {
        matched.* = cap.end;
        return true;
    }
    return false;
}

fn searchFirstCapture(line: []const u8, matched: *usize, regex: [:0]const u8) Error!bool {
    var re = Regex.compile(regex, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer re.deinit();
    if (re.captures(std.testing.allocator, line, .{ .Anchored = true }) catch null) |caps| {
        defer std.testing.allocator.free(caps);
        var i: usize = 1;
        while (i < caps.len) : (i += 1) {
            if (caps[i]) |cap| {
                matched.* = cap.end;
                return true;
            }
        }
        @panic("no matching capture group");
    }
    return false;
}

fn match(line: []const u8, regex: [:0]const u8) Error!bool {
    var re = Regex.compile(regex, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer re.deinit();
    if (re.matches(line, .{ .Anchored = true }) catch null) |cap| {
        return cap.end == line.len;
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

pub fn atxHeadingStart(line: []const u8, matched: *usize) Error!bool {
    if (line[0] != '#') {
        return false;
    }
    return try search(line, matched, "#{1,6}[ \t\r\n]");
}

pub fn thematicBreak(line: []const u8, matched: *usize) Error!bool {
    if (line[0] != '*' and line[0] != '-' and line[0] != '_') {
        return false;
    }
    return try search(line, matched, "(?:(?:\\*[ \t]*){3,}|(?:_[ \t]*){3,}|(?:-[ \t]*){3,})[ \t]*[\r\n]");
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

pub fn setextHeadingLine(line: []const u8, sc: *SetextChar) Error!bool {
    if ((line[0] == '=' or line[0] == '-') and try match(line, "(?:=+|-+)[ \t]*[\r\n]")) {
        sc.* = if (line[0] == '=') .Equals else .Hyphen;
        return true;
    }
    return false;
}

const scheme = "[A-Za-z][A-Za-z0-9.+-]{1,31}";

pub fn autolinkUri(line: []const u8, matched: *usize) Error!bool {
    return search(line, matched, scheme ++ ":[^\\x00-\\x20<>]*>");
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

pub fn autolinkEmail(line: []const u8, matched: *usize) Error!bool {
    return search(line, matched,
        \\[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*>
    );
}

test "autolinkEmail" {
    var matched: usize = undefined;
    testing.expect(!try autolinkEmail("abc>", &matched));
    testing.expect(!try autolinkEmail("abc.def>", &matched));
    testing.expect(!try autolinkEmail("abc@def", &matched));
    testing.expect(try autolinkEmail("abc@def>", &matched));
    testing.expectEqual(@as(usize, 8), matched);
    testing.expect(try autolinkEmail("abc+123!?@96--1>", &matched));
    testing.expectEqual(@as(usize, 16), matched);
}

pub fn openCodeFence(line: []const u8, matched: *usize) Error!bool {
    if (line[0] != '`' and line[0] != '~')
        return false;

    return searchFirstCapture(line, matched, "(?:(`{3,})[^`\r\n\\x00]*|(~{3,})[^\r\n\\x00]*)[\r\n]");
}

test "openCodeFence" {
    var matched: usize = undefined;
    testing.expect(!try openCodeFence("```m", &matched));
    testing.expect(try openCodeFence("```m\n", &matched));
    testing.expectEqual(@as(usize, 3), matched);
    testing.expect(try openCodeFence("~~~~~~m\n", &matched));
    testing.expectEqual(@as(usize, 6), matched);
}

pub fn closeCodeFence(line: []const u8) Error!?usize {
    if (line[0] != '`' and line[0] != '~')
        return null;

    var matched: usize = undefined;
    if (try searchFirstCapture(line, &matched, "(`{3,}|~{3,})[\t ]*[\r\n]")) {
        return matched;
    } else {
        return null;
    }
}

test "closeCodeFence" {
    testing.expectEqual(@as(?usize, null), try closeCodeFence("```m"));
    testing.expectEqual(@as(?usize, 3), try closeCodeFence("```\n"));
    testing.expectEqual(@as(?usize, 6), try closeCodeFence("~~~~~~\r\n"));
}
