const std = @import("std");
const ascii = std.ascii;
const assert = std.debug.assert;

const Options = @import("options.zig").Options;
const nodes = @import("nodes.zig");
const strings = @import("strings.zig");
const scanners = @import("scanners.zig");

pub fn print(allocator: *std.mem.Allocator, options: Options, root: *nodes.AstNode) ![]u8 {
    var formatter = HtmlFormatter.init(allocator, options);
    defer formatter.deinit();

    try formatter.format(root, false);

    return formatter.buffer.toOwnedSlice();
}

const HtmlFormatter = struct {
    allocator: *std.mem.Allocator,
    options: Options,
    buffer: std.ArrayList(u8),
    last_was_lf: bool = true,
    anchor_map: std.StringHashMap(void),

    pub fn init(allocator: *std.mem.Allocator, options: Options) HtmlFormatter {
        return .{
            .allocator = allocator,
            .options = options,
            .buffer = std.ArrayList(u8).init(allocator),
            .anchor_map = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *HtmlFormatter) void {
        var it = self.anchor_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key);
        }
        self.anchor_map.deinit();
    }

    const NEEDS_ESCAPED = strings.createMap("\"&<>");
    const HREF_SAFE = strings.createMap("-_.+!*'(),%#@?=;:/,+&$~abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");

    fn dangerousUrl(input: []const u8) !bool {
        return (try scanners.dangerousUrl(input)) != null;
    }

    // Hack so that there's a Writer.Error.
    const Writer = struct {
        formatter: *HtmlFormatter,
        pub const Error = error{OutOfMemory};

        pub fn writeAll(self: @This(), bytes: []const u8) Error!void {
            try self.formatter.writeAll(bytes);
        }
    };

    fn cr(self: *HtmlFormatter) !void {
        if (!self.last_was_lf) {
            try self.writeAll("\n");
        }
    }

    fn escape(self: *HtmlFormatter, s: []const u8) !void {
        var offset: usize = 0;
        for (s) |c, i| {
            if (NEEDS_ESCAPED[c]) {
                try self.writeAll(s[offset..i]);
                try self.writeAll(switch (c) {
                    '"' => "&quot;",
                    '&' => "&amp;",
                    '<' => "&lt;",
                    '>' => "&gt;",
                    else => unreachable,
                });
                offset = i + 1;
            }
        }
        try self.writeAll(s[offset..]);
    }

    fn escapeHref(self: *HtmlFormatter, s: []const u8) !void {
        var i: usize = 0;
        const size = s.len;

        while (i < size) : (i += 1) {
            const org = i;
            while (i < size and HREF_SAFE[s[i]])
                i += 1;

            if (i > org) {
                try self.writeAll(s[org..i]);
            }

            if (i >= size) {
                break;
            }

            switch (s[i]) {
                '&' => try self.writeAll("&amp;"),
                '\'' => try self.writeAll("&#x27;"),
                else => try std.fmt.format(Writer{ .formatter = self }, "%{X:0>2}", .{s[i]}),
            }
        }
    }

    pub fn writeAll(self: *HtmlFormatter, s: []const u8) !void {
        if (s.len == 0) {
            return;
        }
        try self.buffer.appendSlice(s);
        self.last_was_lf = s[s.len - 1] == '\n';
    }

    fn format(self: *HtmlFormatter, input_node: *nodes.AstNode, plain: bool) !void {
        const Phase = enum { Pre, Post };
        const StackEntry = struct {
            node: *nodes.AstNode,
            plain: bool,
            phase: Phase,
        };

        var stack = std.ArrayList(StackEntry).init(self.allocator);
        defer stack.deinit();

        try stack.append(.{ .node = input_node, .plain = plain, .phase = .Pre });

        while (stack.popOrNull()) |entry| {
            switch (entry.phase) {
                .Pre => {
                    var new_plain: bool = undefined;
                    if (entry.plain) {
                        switch (entry.node.data.value) {
                            .Text, .HtmlInline, .Code => |literal| {
                                try self.escape(literal);
                            },
                            .LineBreak, .SoftBreak => {
                                try self.writeAll(" ");
                            },
                            else => {},
                        }
                        new_plain = entry.plain;
                    } else {
                        try stack.append(.{ .node = entry.node, .plain = false, .phase = .Post });
                        new_plain = try self.fnode(entry.node, true);
                    }

                    var it = entry.node.reverseChildrenIterator();
                    while (it.next()) |ch| {
                        try stack.append(.{ .node = ch, .plain = new_plain, .phase = .Pre });
                    }
                },
                .Post => {
                    assert(!entry.plain);
                    _ = try self.fnode(entry.node, false);
                },
            }
        }
    }

    fn fnode(self: *HtmlFormatter, node: *nodes.AstNode, entering: bool) !bool {
        switch (node.data.value) {
            .Document => {},
            .BlockQuote => {
                try self.cr();
                try self.writeAll(if (entering) "<blockquote>\n" else "</blockquote>");
            },
            .List => |nl| {
                if (entering) {
                    try self.cr();
                    if (nl.list_type == .Bullet) {
                        try self.writeAll("<ul>\n");
                    } else if (nl.start == 1) {
                        try self.writeAll("<ol>\n");
                    } else {
                        try std.fmt.format(Writer{ .formatter = self }, "<ol start=\"{}\">", .{nl.start});
                    }
                } else if (nl.list_type == .Bullet) {
                    try self.writeAll("</ul>\n");
                } else {
                    try self.writeAll("</ol>\n");
                }
            },
            .Item => {
                if (entering) {
                    try self.cr();
                    try self.writeAll("<li>");
                } else {
                    try self.writeAll("</li>\n");
                }
            },
            .Heading => |nch| {
                if (entering) {
                    try self.cr();
                    try std.fmt.format(Writer{ .formatter = self }, "<h{}>", .{nch.level});
                    if (self.options.render.header_anchors) {
                        var text_content = try self.collectText(node);
                        defer self.allocator.free(text_content);
                        var id = try self.anchorize(text_content);
                        try self.writeAll("<a href=\"#");
                        try self.writeAll(id);
                        try self.writeAll("\" id=\"");
                        try self.writeAll(id);
                        try self.writeAll("\"></a>");
                    }
                } else {
                    try std.fmt.format(Writer{ .formatter = self }, "</h{}>\n", .{nch.level});
                }
            },
            .CodeBlock => |ncb| {
                if (entering) {
                    try self.cr();

                    if (ncb.info == null or ncb.info.?.len == 0) {
                        try self.writeAll("<pre><code>");
                    } else {
                        var first_tag: usize = 0;
                        while (first_tag < ncb.info.?.len and !ascii.isSpace(ncb.info.?[first_tag]))
                            first_tag += 1;

                        try self.writeAll("<pre><code class=\"language-");
                        try self.escape(ncb.info.?[0..first_tag]);
                        try self.writeAll("\">");
                    }
                    try self.escape(ncb.literal.items);
                    try self.writeAll("</code></pre>\n");
                }
            },
            .HtmlBlock => |nhb| {
                if (entering) {
                    try self.cr();
                    if (!self.options.render.unsafe) {
                        try self.writeAll("<!-- raw HTML omitted -->");
                    } else if (self.options.extensions.tagfilter) {
                        try self.tagfilterBlock(nhb.literal.items);
                    } else {
                        try self.writeAll(nhb.literal.items);
                    }
                    try self.cr();
                }
            },
            .ThematicBreak => {
                if (entering) {
                    try self.cr();
                    try self.writeAll("<hr />\n");
                }
            },
            .Paragraph => {
                var tight = node.parent != null and node.parent.?.parent != null and switch (node.parent.?.parent.?.data.value) {
                    .List => |nl| nl.tight,
                    else => false,
                };

                if (!tight) {
                    if (entering) {
                        try self.cr();
                        try self.writeAll("<p>");
                    } else {
                        try self.writeAll("</p>\n");
                    }
                }
            },
            .Text => |literal| {
                if (entering) {
                    try self.escape(literal);
                }
            },
            .LineBreak => {
                if (entering) {
                    try self.writeAll("<br />\n");
                }
            },
            .SoftBreak => {
                if (entering) {
                    try self.writeAll(if (self.options.render.hard_breaks) "<br />\n" else "\n");
                }
            },
            .Code => |literal| {
                if (entering) {
                    try self.writeAll("<code>");
                    try self.escape(literal);
                    try self.writeAll("</code>");
                }
            },
            .HtmlInline => |literal| {
                if (entering) {
                    if (!self.options.render.unsafe) {
                        try self.writeAll("<!-- raw HTML omitted -->");
                    } else if (self.options.extensions.tagfilter and tagfilter(literal)) {
                        try self.writeAll("&lt;");
                        try self.writeAll(literal[1..]);
                    } else {
                        try self.writeAll(literal);
                    }
                }
            },
            .Strong => {
                try self.writeAll(if (entering) "<strong>" else "</strong>");
            },
            .Emph => {
                try self.writeAll(if (entering) "<em>" else "</em>");
            },
            .Strikethrough => {
                if (entering) {
                    try self.writeAll("<del>");
                } else {
                    try self.writeAll("</del>");
                }
            },
            .Link => |nl| {
                if (entering) {
                    try self.writeAll("<a href=\"");
                    if (self.options.render.unsafe or !(try dangerousUrl(nl.url))) {
                        try self.escapeHref(nl.url);
                    }
                    if (nl.title.len > 0) {
                        try self.writeAll("\" title=\"");
                        try self.escape(nl.title);
                    }
                    try self.writeAll("\">");
                } else {
                    try self.writeAll("</a>");
                }
            },
            .Image => |nl| {
                if (entering) {
                    try self.writeAll("<img src=\"");
                    if (self.options.render.unsafe or !(try dangerousUrl(nl.url))) {
                        try self.escapeHref(nl.url);
                    }
                    try self.writeAll("\" alt=\"");
                    return true;
                } else {
                    if (nl.title.len > 0) {
                        try self.writeAll("\" title=\"");
                        try self.escape(nl.title);
                    }
                    try self.writeAll("\" />");
                }
            },
            .Table => {
                if (entering) {
                    try self.cr();
                    try self.writeAll("<table>\n");
                } else {
                    if (node.last_child.? != node.first_child.?) {
                        try self.cr();
                        try self.writeAll("</tbody>\n");
                    }
                    try self.cr();
                    try self.writeAll("</table>\n");
                }
            },
            .TableRow => |kind| {
                if (entering) {
                    try self.cr();
                    if (kind == .Header) {
                        try self.writeAll("<thead>\n");
                    } else if (node.prev) |prev| {
                        switch (prev.data.value) {
                            .TableRow => |k| {
                                if (k == .Header)
                                    try self.writeAll("<tbody>\n");
                            },
                            else => {},
                        }
                    }
                    try self.writeAll("<tr>");
                } else {
                    try self.cr();
                    try self.writeAll("</tr>");
                    if (kind == .Header) {
                        try self.cr();
                        try self.writeAll("</thead>");
                    }
                }
            },
            .TableCell => {
                const kind = node.parent.?.data.value.TableRow;
                const alignments = node.parent.?.parent.?.data.value.Table;

                if (entering) {
                    try self.cr();
                    if (kind == .Header) {
                        try self.writeAll("<th");
                    } else {
                        try self.writeAll("<td");
                    }

                    var start = node.parent.?.first_child.?;
                    var i: usize = 0;
                    while (start != node) {
                        i += 1;
                        start = start.next.?;
                    }

                    switch (alignments[i]) {
                        .Left => try self.writeAll(" align=\"left\""),
                        .Right => try self.writeAll(" align=\"right\""),
                        .Center => try self.writeAll(" align=\"center\""),
                        .None => {},
                    }

                    try self.writeAll(">");
                } else if (kind == .Header) {
                    try self.writeAll("</th>");
                } else {
                    try self.writeAll("</td>");
                }
            },
        }
        return false;
    }

    fn collectText(self: *HtmlFormatter, node: *nodes.AstNode) ![]u8 {
        var out = std.ArrayList(u8).init(self.allocator);
        try collectTextInto(&out, node);
        return out.toOwnedSlice();
    }

    fn collectTextInto(out: *std.ArrayList(u8), node: *nodes.AstNode) std.mem.Allocator.Error!void {
        switch (node.data.value) {
            .Text, .Code => |literal| {
                try out.appendSlice(literal);
            },
            .LineBreak, .SoftBreak => try out.append(' '),
            else => {
                var it = node.first_child;
                while (it) |child| {
                    try collectTextInto(out, child);
                    it = child.next;
                }
            },
        }
    }

    fn anchorize(self: *HtmlFormatter, header: []const u8) ![]const u8 {
        var lower = try strings.toLower(self.allocator, header);
        defer self.allocator.free(lower);
        var removed = try scanners.removeAnchorizeRejectedChars(self.allocator, lower);
        defer self.allocator.free(removed);

        for (removed) |*c| {
            if (c.* == ' ') c.* = '-';
        }

        var uniq: usize = 0;
        while (true) {
            var anchor = if (uniq == 0)
                try self.allocator.dupe(u8, removed)
            else
                try std.fmt.allocPrint(self.allocator, "{}-{}", .{ removed, uniq });
            errdefer self.allocator.free(anchor);

            var getPut = try self.anchor_map.getOrPut(anchor);
            if (!getPut.found_existing) {
                // anchor now belongs in anchor_map.
                return anchor;
            }

            self.allocator.free(anchor);

            uniq += 1;
        }
    }

    const TAGFILTER_BLACKLIST = [_][]const u8{
        "title",
        "textarea",
        "style",
        "xmp",
        "iframe",
        "noembed",
        "noframes",
        "script",
        "plaintext",
    };
    fn tagfilter(literal: []const u8) bool {
        if (literal.len < 3 or literal[0] != '<')
            return false;

        var i: usize = 1;
        if (literal[i] == '/')
            i += 1;

        for (TAGFILTER_BLACKLIST) |t| {
            const j = i + t.len;
            if (literal.len > j and std.ascii.eqlIgnoreCase(t, literal[i..j])) {
                return ascii.isSpace(literal[j]) or
                    literal[j] == '>' or
                    (literal[j] == '/' and literal.len >= j + 2 and literal[j + 1] == '>');
            }
        }

        return false;
    }

    fn tagfilterBlock(self: *HtmlFormatter, input: []const u8) !void {
        const size = input.len;
        var i: usize = 0;

        while (i < size) {
            const org = i;
            while (i < size and input[i] != '<') : (i += 1) {}
            if (i > org) {
                try self.writeAll(input[org..i]);
            }
            if (i >= size) {
                break;
            }
            if (tagfilter(input[i..])) {
                try self.writeAll("&lt;");
            } else {
                try self.writeAll("<");
            }
            i += 1;
        }
    }
};

test "escaping works as expected" {
    var formatter = HtmlFormatter.init(std.testing.allocator, .{});
    defer formatter.deinit();

    try formatter.escape("<hello & goodbye>");
    std.testing.expectEqualStrings("&lt;hello &amp; goodbye&gt;", formatter.buffer.items);
    formatter.buffer.deinit();
}
test "lowercase anchor generation" {
    var formatter = HtmlFormatter.init(std.testing.allocator, .{});
    defer formatter.deinit();

    std.testing.expectEqualStrings("yés", try formatter.anchorize("YÉS"));
}
