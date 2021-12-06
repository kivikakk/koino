const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const ascii = std.ascii;

const nodes = @import("nodes.zig");
const htmlentities = @import("htmlentities");
const zunicode = @import("zunicode");

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
    try testing.expect(isBlank(""));
    try testing.expect(isBlank("\nx"));
    try testing.expect(isBlank("    \t\t  \r"));
    try testing.expect(!isBlank("e"));
    try testing.expect(!isBlank("   \t    e "));
}

const SPACES = "\t\n\x0b\x0c\r ";

pub fn ltrim(s: []const u8) []const u8 {
    return mem.trimLeft(u8, s, SPACES);
}

test "ltrim" {
    try testing.expectEqualStrings("abc", ltrim("abc"));
    try testing.expectEqualStrings("abc", ltrim("   abc"));
    try testing.expectEqualStrings("abc", ltrim("      \n\n \t\r abc"));
    try testing.expectEqualStrings("abc \n zz \n   ", ltrim("\nabc \n zz \n   "));
}

pub fn rtrim(s: []const u8) []const u8 {
    return mem.trimRight(u8, s, SPACES);
}

test "rtrim" {
    try testing.expectEqualStrings("abc", rtrim("abc"));
    try testing.expectEqualStrings("abc", rtrim("abc   "));
    try testing.expectEqualStrings("abc", rtrim("abc      \n\n \t\r "));
    try testing.expectEqualStrings("  \nabc \n zz", rtrim("  \nabc \n zz \n"));
}

pub fn trim(s: []const u8) []const u8 {
    return mem.trim(u8, s, SPACES);
}

test "trim" {
    try testing.expectEqualStrings("abc", trim("abc"));
    try testing.expectEqualStrings("abc", trim("  abc   "));
    try testing.expectEqualStrings("abc", trim(" abc      \n\n \t\r "));
    try testing.expectEqualStrings("abc \n zz", trim("  \nabc \n zz \n"));
}

pub fn trimIt(al: *std.ArrayList(u8)) void {
    var trimmed = trim(al.items);
    if (al.items.ptr == trimmed.ptr and al.items.len == trimmed.len) return;
    std.mem.copy(u8, al.items, trimmed);
    al.items.len = trimmed.len;
}

test "trimIt" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try buf.appendSlice("abc");
    trimIt(&buf);
    try std.testing.expectEqualStrings("abc", buf.items);

    buf.items.len = 0;
    try buf.appendSlice("  \tabc");
    trimIt(&buf);
    try std.testing.expectEqualStrings("abc", buf.items);

    buf.items.len = 0;
    try buf.appendSlice(" \r abc  \n ");
    trimIt(&buf);
    try std.testing.expectEqualStrings("abc", buf.items);
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
    try testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz"));
    try testing.expectEqualStrings("xyz#", chopTrailingHashtags("xyz#"));
    try testing.expectEqualStrings("xyz###", chopTrailingHashtags("xyz###"));
    try testing.expectEqualStrings("xyz###", chopTrailingHashtags("xyz###  "));
    try testing.expectEqualStrings("xyz###", chopTrailingHashtags("xyz###  #"));
    try testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz  "));
    try testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz  ##"));
    try testing.expectEqualStrings("xyz", chopTrailingHashtags("xyz  ##"));
}

pub fn normalizeCode(allocator: mem.Allocator, s: []const u8) ![]u8 {
    var code = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer code.deinit();

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

    if (contains_nonspace and code.items.len != 0 and code.items[0] == ' ' and code.items[code.items.len - 1] == ' ') {
        _ = code.orderedRemove(0);
        _ = code.pop();
    }

    return code.toOwnedSlice();
}

const Case = struct {
    in: []const u8,
    out: []const u8,
};

fn testCases(function: fn (mem.Allocator, []const u8) anyerror![]u8, cases: []const Case) !void {
    for (cases) |case| {
        const result = try function(std.testing.allocator, case.in);
        defer std.testing.allocator.free(result);
        try testing.expectEqualStrings(case.out, result);
    }
}

test "normalizeCode" {
    try testCases(normalizeCode, &[_]Case{
        .{ .in = "qwe", .out = "qwe" },
        .{ .in = " qwe ", .out = "qwe" },
        .{ .in = "  qwe  ", .out = " qwe " },
        .{ .in = " abc\rdef'\r\ndef ", .out = "abc def' def" },
    });
}

pub fn removeTrailingBlankLines(line: *std.ArrayList(u8)) void {
    var i = line.items.len - 1;
    while (true) : (i -= 1) {
        const c = line.items[i];

        if (c != ' ' and c != '\t' and !isLineEndChar(c)) {
            break;
        }

        if (i == 0) {
            line.items.len = 0;
            return;
        }
    }

    while (i < line.items.len) : (i += 1) {
        if (!isLineEndChar(line.items[i])) continue;
        line.items.len = i;
        break;
    }
}

test "removeTrailingBlankLines" {
    const cases = [_]Case{
        .{ .in = "\n\n   \r\t\n ", .out = "" },
        .{ .in = "yep\nok\n\n  ", .out = "yep\nok" },
        .{ .in = "yep  ", .out = "yep  " },
    };

    var line = std.ArrayList(u8).init(std.testing.allocator);
    defer line.deinit();
    for (cases) |case| {
        line.items.len = 0;
        try line.appendSlice(case.in);
        removeTrailingBlankLines(&line);
        try testing.expectEqualStrings(case.out, line.items);
    }
}

fn encodeUtf8Into(in_cp: u21, al: *std.ArrayList(u8)) !void {
    // utf8Encode throws:
    // - Utf8CannotEncodeSurrogateHalf, which we guard against that by
    //   rewriting 0xd800..0xe0000 to 0xfffd.
    // - CodepointTooLarge, which we guard against by rewriting 0x110000+
    //   to 0xfffd.
    var cp = in_cp;
    if (cp == 0 or (cp >= 0xd800 and cp <= 0xdfff) or cp >= 0x110000) {
        cp = 0xFFFD;
    }
    var sequence = [4]u8{ 0, 0, 0, 0 };
    const len = std.unicode.utf8Encode(cp, &sequence) catch unreachable;
    try al.appendSlice(sequence[0..len]);
}

const ENTITY_MIN_LENGTH: u8 = 2;
const ENTITY_MAX_LENGTH: u8 = 32;

pub fn unescapeInto(text: []const u8, out: *std.ArrayList(u8)) !?usize {
    if (text.len >= 3 and text[0] == '#') {
        var codepoint: u32 = 0;
        var i: usize = 0;

        const num_digits = block: {
            if (ascii.isDigit(text[1])) {
                i = 1;
                while (i < text.len and ascii.isDigit(text[i])) {
                    codepoint = (codepoint * 10) + (@as(u32, text[i]) - '0');
                    codepoint = std.math.min(codepoint, 0x11_0000);
                    i += 1;
                }
                break :block i - 1;
            } else if (text[1] == 'x' or text[1] == 'X') {
                i = 2;
                while (i < text.len and ascii.isXDigit(text[i])) {
                    codepoint = (codepoint * 16) + (@as(u32, text[i]) | 32) % 39 - 9;
                    codepoint = std.math.min(codepoint, 0x11_0000);
                    i += 1;
                }
                break :block i - 2;
            }
            break :block 0;
        };

        if (num_digits >= 1 and num_digits <= 8 and i < text.len and text[i] == ';') {
            try encodeUtf8Into(@truncate(u21, codepoint), out);
            return i + 1;
        }
    }

    const size = std.math.min(text.len, ENTITY_MAX_LENGTH);
    var i = ENTITY_MIN_LENGTH;
    while (i < size) : (i += 1) {
        if (text[i] == ' ')
            return null;
        if (text[i] == ';') {
            var key = [_]u8{'&'} ++ [_]u8{';'} ** (ENTITY_MAX_LENGTH + 1);
            mem.copy(u8, key[1..], text[0..i]);

            if (htmlentities.lookup(key[0 .. i + 2])) |item| {
                try out.appendSlice(item.characters);
                return i + 1;
            }
        }
    }

    return null;
}

fn unescapeHtmlInto(html: []const u8, out: *std.ArrayList(u8)) !void {
    var size = html.len;
    var i: usize = 0;

    while (i < size) {
        const org = i;

        while (i < size and html[i] != '&') : (i += 1) {}

        if (i > org) {
            if (org == 0 and i >= size) {
                try out.appendSlice(html);
                return;
            }

            try out.appendSlice(html[org..i]);
        }

        if (i >= size)
            return;

        i += 1;

        if (try unescapeInto(html[i..], out)) |unescaped_size| {
            i += unescaped_size;
        } else {
            try out.append('&');
        }
    }
}

pub fn unescapeHtml(allocator: mem.Allocator, html: []const u8) ![]u8 {
    var al = std.ArrayList(u8).init(allocator);
    errdefer al.deinit();
    try unescapeHtmlInto(html, &al);
    return al.toOwnedSlice();
}

test "unescapeHtml" {
    try testCases(unescapeHtml, &[_]Case{
        .{ .in = "&#116;&#101;&#115;&#116;", .out = "test" },
        .{ .in = "&#12486;&#12473;&#12488;", .out = "テスト" },
        .{ .in = "&#x74;&#x65;&#X73;&#X74;", .out = "test" },
        .{ .in = "&#x30c6;&#x30b9;&#X30c8;", .out = "テスト" },

        // "Although HTML5 does accept some entity references without a trailing semicolon
        // (such as &copy), these are not recognized here, because it makes the grammar too
        // ambiguous:"
        .{ .in = "&hellip;&eacute&Eacute;&rrarr;&oS;", .out = "…&eacuteÉ⇉Ⓢ" },
    });
}

pub fn cleanAutolink(allocator: mem.Allocator, url: []const u8, kind: nodes.AutolinkType) ![]u8 {
    var trimmed = trim(url);
    if (trimmed.len == 0)
        return &[_]u8{};

    var buf = try std.ArrayList(u8).initCapacity(allocator, trimmed.len);
    errdefer buf.deinit();
    if (kind == .Email)
        try buf.appendSlice("mailto:");

    try unescapeHtmlInto(trimmed, &buf);
    return buf.toOwnedSlice();
}

test "cleanAutolink" {
    var email = try cleanAutolink(std.testing.allocator, "  hello&#x40;world.example ", .Email);
    defer std.testing.allocator.free(email);
    try testing.expectEqualStrings("mailto:hello@world.example", email);

    var uri = try cleanAutolink(std.testing.allocator, "  www&#46;com ", .URI);
    defer std.testing.allocator.free(uri);
    try testing.expectEqualStrings("www.com", uri);
}

fn unescape(allocator: mem.Allocator, s: []const u8) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer buffer.deinit();
    var r: usize = 0;

    while (r < s.len) : (r += 1) {
        if (s[r] == '\\' and r + 1 < s.len and ascii.isPunct(s[r + 1]))
            r += 1;
        try buffer.append(s[r]);
    }
    return buffer.toOwnedSlice();
}

pub fn cleanUrl(allocator: mem.Allocator, url: []const u8) ![]u8 {
    var trimmed = trim(url);
    if (trimmed.len == 0)
        return &[_]u8{};

    var b = try unescapeHtml(allocator, trimmed);
    defer allocator.free(b);
    return unescape(allocator, b);
}

test "cleanUrl" {
    var url = try cleanUrl(std.testing.allocator, "  \\(hello\\)&#x40;world  ");
    defer std.testing.allocator.free(url);
    try testing.expectEqualStrings("(hello)@world", url);
}

pub fn cleanTitle(allocator: mem.Allocator, title: []const u8) ![]u8 {
    if (title.len == 0)
        return &[_]u8{};

    const first = title[0];
    const last = title[title.len - 1];
    var b = if ((first == '\'' and last == '\'') or (first == '(' and last == ')') or (first == '"' and last == '"'))
        try unescapeHtml(allocator, title[1 .. title.len - 1])
    else
        try unescapeHtml(allocator, title);
    defer allocator.free(b);
    return unescape(allocator, b);
}

test "cleanTitle" {
    try testCases(cleanTitle, &[_]Case{
        .{ .in = "\\'title", .out = "'title" },
        .{ .in = "'title'", .out = "title" },
        .{ .in = "(&#x74;&#x65;&#X73;&#X74;)", .out = "test" },
        .{ .in = "\"&#x30c6;&#x30b9;&#X30c8;\"", .out = "テスト" },
        .{ .in = "'&hellip;&eacute&Eacute;&rrarr;&oS;'", .out = "…&eacuteÉ⇉Ⓢ" },
    });
}

pub fn normalizeLabel(allocator: mem.Allocator, s: []const u8) ![]u8 {
    var trimmed = trim(s);
    var buffer = try std.ArrayList(u8).initCapacity(allocator, trimmed.len);
    errdefer buffer.deinit();
    var last_was_whitespace = false;

    var view = std.unicode.Utf8View.initUnchecked(trimmed);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        var rune = @intCast(i32, cp);
        if (zunicode.isSpace(rune)) {
            if (!last_was_whitespace) {
                last_was_whitespace = true;
                try buffer.append(' ');
            }
        } else {
            last_was_whitespace = false;
            var lower = zunicode.toLower(rune);
            try encodeUtf8Into(@intCast(u21, lower), &buffer);
        }
    }
    return buffer.toOwnedSlice();
}

test "normalizeLabel" {
    try testCases(normalizeLabel, &[_]Case{
        .{ .in = "Hello", .out = "hello" },
        .{ .in = "   Y        E  S  ", .out = "y e s" },
        .{ .in = "yÉs", .out = "yés" },
    });
}

pub fn toLower(allocator: mem.Allocator, s: []const u8) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer buffer.deinit();
    var view = try std.unicode.Utf8View.init(s);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        var rune = @intCast(i32, cp);
        var lower = zunicode.toLower(rune);
        try encodeUtf8Into(@intCast(u21, lower), &buffer);
    }
    return buffer.toOwnedSlice();
}

test "toLower" {
    try testCases(toLower, &[_]Case{
        .{ .in = "Hello", .out = "hello" },
        .{ .in = "ΑαΒβΓγΔδΕεΖζΗηΘθΙιΚκΛλΜμ", .out = "ααββγγδδεεζζηηθθιικκλλμμ" },
        .{ .in = "АаБбВвГгДдЕеЁёЖжЗзИиЙйКкЛлМмНнОоПпРрСсТтУуФфХхЦцЧчШшЩщЪъЫыЬьЭэЮюЯя", .out = "ааббввггддееёёжжззииййккллммннооппррссттууффххццччшшщщъъыыььээююяя" },
    });
}

pub fn createMap(chars: []const u8) [256]bool {
    var arr = [_]bool{false} ** 256;
    for (chars) |c| {
        arr[c] = true;
    }
    return arr;
}

test "createMap" {
    comptime {
        const m = createMap("abcxyz");
        try testing.expect(m['a']);
        try testing.expect(m['b']);
        try testing.expect(m['c']);
        try testing.expect(!m['d']);
        try testing.expect(!m['e']);
        try testing.expect(!m['f']);
        try testing.expect(m['x']);
        try testing.expect(!m[0]);
    }
}
