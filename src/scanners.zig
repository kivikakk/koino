const std = @import("std");
const testing = std.testing;
const Regex = @import("libpcre").Regex;

const Error = error{OutOfMemory};

// TODO: compile once.
fn search(line: []const u8, matched: ?*usize, regex: [:0]const u8) Error!bool {
    var re = Regex.compile(regex, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer re.deinit();
    if (re.matches(line, .{ .Anchored = true }) catch null) |cap| {
        if (matched) |m| m.* = cap.end;
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
    if ((line[0] == '=' or line[0] == '-') and try search(line, null, "(?:=+|-+)[ \t]*[\r\n]")) {
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

pub fn htmlBlockStart(line: []const u8, matched: *usize) Error!bool {
    if (line[0] != '<')
        return false;

    if (try search(line, null, "<(?i:script|pre|style)[ \t\\x0b\\x0c\r\n>]")) {
        matched.* = 1;
    } else if (std.mem.startsWith(u8, line, "<!--")) {
        matched.* = 2;
    } else if (std.mem.startsWith(u8, line, "<?")) {
        matched.* = 3;
    } else if (try search(line, null, "<![A-Z]")) {
        matched.* = 4;
    } else if (std.mem.startsWith(u8, line, "<![CDATA[")) {
        matched.* = 5;
    } else if (try search(line, null, "</?(:i?address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|source|title|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:[ \t\\x0b\\x0c\r\n>]|/>)")) {
        matched.* = 6;
    } else {
        return false;
    }
    return true;
}

test "htmlBlockStart" {
    var matched: usize = undefined;

    testing.expect(!try htmlBlockStart("<xyz", &matched));
    testing.expect(try htmlBlockStart("<Script\r", &matched));
    testing.expectEqual(@as(usize, 1), matched);
    testing.expect(try htmlBlockStart("<pre>", &matched));
    testing.expectEqual(@as(usize, 1), matched);
    testing.expect(try htmlBlockStart("<!-- h", &matched));
    testing.expectEqual(@as(usize, 2), matched);
    testing.expect(try htmlBlockStart("<?m", &matched));
    testing.expectEqual(@as(usize, 3), matched);
    testing.expect(try htmlBlockStart("<!Q", &matched));
    testing.expectEqual(@as(usize, 4), matched);
    testing.expect(try htmlBlockStart("<![CDATA[\n", &matched));
    testing.expectEqual(@as(usize, 5), matched);
    testing.expect(try htmlBlockStart("</ul>", &matched));
    testing.expectEqual(@as(usize, 6), matched);
    testing.expect(try htmlBlockStart("<figcaption/>", &matched));
    testing.expectEqual(@as(usize, 6), matched);
    testing.expect(!try htmlBlockStart("<xhtml>", &matched));
}

const space_char = "[ \t\\x0b\\x0c\r\n]";
const tag_name = "(?:[A-Za-z][A-Za-z0-9-]*)";
const close_tag = "(?:/" ++ tag_name ++ space_char ++ "*>)";
const attribute_name = "(?:[a-zA_Z_:][a-zA-Z0-9:._-]*)";
const attribute_value = "(?:(?:[^ \t\r\n\\x0b\\x0c\"'=<>`\\x00]+)|(?:'[^\\x00']*')|(?:\"[^\\x00\"]*\"))";
const attribute_value_spec = "(?:" ++ space_char ++ "*=" ++ space_char ++ "*" ++ attribute_value ++ ")";
const attribute = "(?:" ++ space_char ++ "+" ++ attribute_name ++ attribute_value_spec ++ "?)";
const open_tag = "(?:" ++ tag_name ++ attribute ++ "*" ++ space_char ++ "*/?>)";

pub fn htmlBlockStart7(line: []const u8, matched: *usize) Error!bool {
    if (try search(line, null, "<(?:" ++ open_tag ++ "|" ++ close_tag ++ ")[\t\\x0c ]*[\r\n]")) {
        matched.* = 7;
        return true;
    }
    return false;
}

test "htmlBlockStart7" {
    var matched: usize = 1;

    testing.expect(!try htmlBlockStart7("<a", &matched));
    testing.expect(try htmlBlockStart7("<a>  \n", &matched));
    testing.expectEqual(@as(usize, 7), matched);
    testing.expect(try htmlBlockStart7("<b2/>\r", &matched));
    testing.expect(try htmlBlockStart7("<b2\ndata=\"foo\" >\t\x0c\n", &matched));
    testing.expect(try htmlBlockStart7("<a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 />\n", &matched));
    testing.expect(!try htmlBlockStart7("<a h*#ref=\"hi\">\n", &matched));
}
