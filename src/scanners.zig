const std = @import("std");
const testing = std.testing;
const Regex = @import("libpcre").Regex;

const Error = error{OutOfMemory};

// TODO: compile once.
fn search(line: []const u8, regex: [:0]const u8) Error!?usize {
    var re = Regex.compile(regex, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer re.deinit();
    if (re.matches(line, .{ .Anchored = true }) catch null) |cap| {
        return cap.end;
    }
    return null;
}

pub fn unwrap(value: Error!?usize, out: *usize) Error!bool {
    if (value) |maybe_val| {
        if (maybe_val) |val| {
            out.* = val;
            return true;
        }
        return false;
    } else |err| {
        return err;
    }
}

fn searchFirstCapture(line: []const u8, regex: [:0]const u8) Error!?usize {
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
                return cap.end;
            }
        }
        @panic("no matching capture group");
    }
    return null;
}

pub fn atxHeadingStart(line: []const u8) Error!?usize {
    if (line[0] != '#') {
        return null;
    }
    return search(line, "#{1,6}[ \t\r\n]");
}

pub fn thematicBreak(line: []const u8) Error!?usize {
    if (line[0] != '*' and line[0] != '-' and line[0] != '_') {
        return null;
    }
    return search(line, "(?:(?:\\*[ \t]*){3,}|(?:_[ \t]*){3,}|(?:-[ \t]*){3,})[ \t]*[\r\n]");
}

test "thematicBreak" {
    var matched: usize = undefined;
    testing.expectEqual(@as(?usize, null), try thematicBreak("hello"));
    testing.expectEqual(@as(?usize, 4), try thematicBreak("***\n"));
    testing.expectEqual(@as(?usize, 21), try thematicBreak("-          -   -    \r"));
    testing.expectEqual(@as(?usize, 21), try thematicBreak("-          -   -    \r\nxyz"));
}

pub const SetextChar = enum {
    Equals,
    Hyphen,
};

pub fn setextHeadingLine(line: []const u8, sc: *SetextChar) Error!bool {
    if ((line[0] == '=' or line[0] == '-') and (try search(line, "(?:=+|-+)[ \t]*[\r\n]")) != null) {
        sc.* = if (line[0] == '=') .Equals else .Hyphen;
        return true;
    }
    return false;
}

const scheme = "[A-Za-z][A-Za-z0-9.+-]{1,31}";

pub fn autolinkUri(line: []const u8) Error!?usize {
    return search(line, scheme ++ ":[^\\x00-\\x20<>]*>");
}

test "autolinkUri" {
    testing.expectEqual(@as(?usize, null), try autolinkUri("www.google.com>"));
    testing.expectEqual(@as(?usize, 23), try autolinkUri("https://www.google.com>"));
    testing.expectEqual(@as(?usize, 7), try autolinkUri("a+b-c:>"));
    testing.expectEqual(@as(?usize, null), try autolinkUri("a+b-c:"));
}

pub fn autolinkEmail(line: []const u8) Error!?usize {
    return search(line,
        \\[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*>
    );
}

test "autolinkEmail" {
    testing.expectEqual(@as(?usize, null), try autolinkEmail("abc>"));
    testing.expectEqual(@as(?usize, null), try autolinkEmail("abc.def>"));
    testing.expectEqual(@as(?usize, null), try autolinkEmail("abc@def"));
    testing.expectEqual(@as(?usize, 8), try autolinkEmail("abc@def>"));
    testing.expectEqual(@as(?usize, 16), try autolinkEmail("abc+123!?@96--1>"));
}

pub fn openCodeFence(line: []const u8) Error!?usize {
    if (line[0] != '`' and line[0] != '~')
        return null;

    return searchFirstCapture(line, "(?:(`{3,})[^`\r\n\\x00]*|(~{3,})[^\r\n\\x00]*)[\r\n]");
}

test "openCodeFence" {
    testing.expectEqual(@as(?usize, null), try openCodeFence("```m"));
    testing.expectEqual(@as(?usize, 3), try openCodeFence("```m\n"));
    testing.expectEqual(@as(?usize, 6), try openCodeFence("~~~~~~m\n"));
}

pub fn closeCodeFence(line: []const u8) Error!?usize {
    if (line[0] != '`' and line[0] != '~')
        return null;

    return searchFirstCapture(line, "(`{3,}|~{3,})[\t ]*[\r\n]");
}

test "closeCodeFence" {
    testing.expectEqual(@as(?usize, null), try closeCodeFence("```m"));
    testing.expectEqual(@as(?usize, 3), try closeCodeFence("```\n"));
    testing.expectEqual(@as(?usize, 6), try closeCodeFence("~~~~~~\r\n"));
}

pub fn htmlBlockEnd1(line: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(line, "</script>") != null or
        std.ascii.indexOfIgnoreCase(line, "</pre>") != null or
        std.ascii.indexOfIgnoreCase(line, "</style>") != null;
}

test "htmlBlockEnd1" {
    testing.expect(htmlBlockEnd1(" xyz </script> "));
    testing.expect(htmlBlockEnd1(" xyz </SCRIPT> "));
    testing.expect(!htmlBlockEnd1(" xyz </ script> "));
}

pub fn htmlBlockEnd2(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "-->") != null;
}

pub fn htmlBlockEnd3(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "?>") != null;
}

pub fn htmlBlockEnd4(line: []const u8) bool {
    return std.mem.indexOfScalar(u8, line, '>') != null;
}

pub fn htmlBlockEnd5(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "]]>") != null;
}

pub fn htmlBlockStart(line: []const u8, sc: *usize) Error!bool {
    if (line[0] != '<')
        return false;

    if ((try search(line, "<(?i:script|pre|style)[ \t\\x0b\\x0c\r\n>]")) != null) {
        sc.* = 1;
    } else if (std.mem.startsWith(u8, line, "<!--")) {
        sc.* = 2;
    } else if (std.mem.startsWith(u8, line, "<?")) {
        sc.* = 3;
    } else if ((try search(line, "<![A-Z]")) != null) {
        sc.* = 4;
    } else if (std.mem.startsWith(u8, line, "<![CDATA[")) {
        sc.* = 5;
    } else if ((try search(line, "</?(?i:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|source|title|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:[ \t\\x0b\\x0c\r\n>]|/>)")) != null) {
        sc.* = 6;
    } else {
        return false;
    }
    return true;
}

test "htmlBlockStart" {
    var sc: usize = undefined;

    testing.expect(!try htmlBlockStart("<xyz", &sc));
    testing.expect(try htmlBlockStart("<Script\r", &sc));
    testing.expectEqual(@as(usize, 1), sc);
    testing.expect(try htmlBlockStart("<pre>", &sc));
    testing.expectEqual(@as(usize, 1), sc);
    testing.expect(try htmlBlockStart("<!-- h", &sc));
    testing.expectEqual(@as(usize, 2), sc);
    testing.expect(try htmlBlockStart("<?m", &sc));
    testing.expectEqual(@as(usize, 3), sc);
    testing.expect(try htmlBlockStart("<!Q", &sc));
    testing.expectEqual(@as(usize, 4), sc);
    testing.expect(try htmlBlockStart("<![CDATA[\n", &sc));
    testing.expectEqual(@as(usize, 5), sc);
    testing.expect(try htmlBlockStart("</ul>", &sc));
    testing.expectEqual(@as(usize, 6), sc);
    testing.expect(try htmlBlockStart("<figcaption/>", &sc));
    testing.expectEqual(@as(usize, 6), sc);
    testing.expect(!try htmlBlockStart("<xhtml>", &sc));
}

const space_char = "[ \t\\x0b\\x0c\r\n]";
const tag_name = "(?:[A-Za-z][A-Za-z0-9-]*)";
const close_tag = "(?:/" ++ tag_name ++ space_char ++ "*>)";
const attribute_name = "(?:[a-zA_Z_:][a-zA-Z0-9:._-]*)";
const attribute_value = "(?:(?:[^ \t\r\n\\x0b\\x0c\"'=<>`\\x00]+)|(?:'[^\\x00']*')|(?:\"[^\\x00\"]*\"))";
const attribute_value_spec = "(?:" ++ space_char ++ "*=" ++ space_char ++ "*" ++ attribute_value ++ ")";
const attribute = "(?:" ++ space_char ++ "+" ++ attribute_name ++ attribute_value_spec ++ "?)";
const open_tag = "(?:" ++ tag_name ++ attribute ++ "*" ++ space_char ++ "*/?>)";

pub fn htmlBlockStart7(line: []const u8, sc: *usize) Error!bool {
    if ((try search(line, "<(?:" ++ open_tag ++ "|" ++ close_tag ++ ")[\t\\x0c ]*[\r\n]")) != null) {
        sc.* = 7;
        return true;
    }
    return false;
}

test "htmlBlockStart7" {
    var sc: usize = 1;

    testing.expect(!try htmlBlockStart7("<a", &sc));
    testing.expect(try htmlBlockStart7("<a>  \n", &sc));
    testing.expectEqual(@as(usize, 7), sc);
    testing.expect(try htmlBlockStart7("<b2/>\r", &sc));
    testing.expect(try htmlBlockStart7("<b2\ndata=\"foo\" >\t\x0c\n", &sc));
    testing.expect(try htmlBlockStart7("<a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 />\n", &sc));
    testing.expect(!try htmlBlockStart7("<a h*#ref=\"hi\">\n", &sc));
}

const html_comment = "(?:!---->|(?:!---?[^\\x00>-](?:-?[^\\x00-])*-->))";
const processing_instruction = "(?:\\?(?:[^?>\\x00]+|\\?[^>\\x00]|>)*\\?>)";
const declaration = "(?:![A-Z]+" ++ space_char ++ "+[^>\\x00]*>)";
const cdata = "(?:!\\[CDATA\\[(?:[^\\]\\x00]+|\\][^\\]\\x00]|\\]\\][^>\\x00])*]]>)";

pub fn htmlTag(line: []const u8) Error!?usize {
    return search(line, "(?:" ++ open_tag ++ "|" ++ close_tag ++ "|" ++ html_comment ++ "|" ++ processing_instruction ++ "|" ++ declaration ++ "|" ++ cdata ++ ")");
}

test "htmlTag" {
    testing.expectEqual(@as(?usize, 6), try htmlTag("!---->"));
    testing.expectEqual(@as(?usize, 9), try htmlTag("!--x-y-->"));
    testing.expectEqual(@as(?usize, 5), try htmlTag("?zy?>"));
    testing.expectEqual(@as(?usize, 6), try htmlTag("?z?y?>"));
    testing.expectEqual(@as(?usize, 14), try htmlTag("!ABCD aoea@#&>"));
    testing.expectEqual(@as(?usize, 11), try htmlTag("![CDATA[]]>"));
    testing.expectEqual(@as(?usize, 20), try htmlTag("![CDATA[a b\n c d ]]>"));
    testing.expectEqual(@as(?usize, 23), try htmlTag("![CDATA[\r]abc]].>\n]>]]>"));
}

pub fn spacechars(line: []const u8) Error!?usize {
    return search(line, space_char ++ "+");
}

const link_title = "(?:\"(?:\\\\.|[^\"\\x00])*\"|'(?:\\\\.|[^'\\x00])*'|\\((?:\\\\.|[^()\\x00])*\\))";

pub fn linkTitle(line: []const u8) Error!?usize {
    return search(line, link_title);
}

test "linkTitle" {
    testing.expectEqual(@as(?usize, null), try linkTitle("\"xyz"));
    testing.expectEqual(@as(?usize, 5), try linkTitle("\"xyz\""));
    testing.expectEqual(@as(?usize, 7), try linkTitle("\"x\\\"yz\""));
    testing.expectEqual(@as(?usize, null), try linkTitle("'xyz"));
    testing.expectEqual(@as(?usize, 5), try linkTitle("'xyz'"));
    testing.expectEqual(@as(?usize, null), try linkTitle("(xyz"));
    testing.expectEqual(@as(?usize, 5), try linkTitle("(xyz)"));
}

const dangerous_url = "(?:data:(?!png|gif|jpeg|webp)|javascript:|vbscript:|file:)";

pub fn dangerousUrl(line: []const u8) Error!?usize {
    return search(line, dangerous_url);
}

test "dangerousUrl" {
    testing.expectEqual(@as(?usize, null), try dangerousUrl("http://thing"));
    testing.expectEqual(@as(?usize, 5), try dangerousUrl("data:xyz"));
    testing.expectEqual(@as(?usize, null), try dangerousUrl("data:png"));
    testing.expectEqual(@as(?usize, null), try dangerousUrl("data:webp"));
    testing.expectEqual(@as(?usize, 5), try dangerousUrl("data:a"));
    testing.expectEqual(@as(?usize, 11), try dangerousUrl("javascript:"));
}

const table_spacechar = "[ \t\\x0b\\x0c]";
const table_newline = "(?:\r?\n)";
const table_marker = "(?:" ++ table_spacechar ++ "*:?-+:?" ++ table_spacechar ++ "*)";
const table_cell = "(?:(\\\\.|[^|\r\n])*)";

pub fn tableStart(line: []const u8) Error!?usize {
    return search(line, "\\|?" ++ table_marker ++ "(?:\\|" ++ table_marker ++ ")*\\|?" ++ table_spacechar ++ "*" ++ table_newline);
}

test "tableStart" {
    unreachable;
}

pub fn tableCell(line: []const u8) Error!?usize {
    return search(line, table_cell);
}

test "tableCell" {
    unreachable;
}

pub fn tableCellEnd(line: []const u8) Error!?usize {
    return search(line, "\\|" ++ table_spacechar ++ "*" ++ table_newline ++ "?");
}

test "tableCellEnd" {
    unreachable;
}
pub fn tableRowEnd(line: []const u8) Error!?usize {
    return search(line, table_spacechar ++ "*" ++ table_newline);
}

test "tableRowEnd" {
    unreachable;
}
