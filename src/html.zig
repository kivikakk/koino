const std = @import("std");
const p = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

const Options = @import("options.zig").Options;
const nodes = @import("nodes.zig");
const ctype = @import("ctype.zig");

pub fn print(allocator: *mem.Allocator, options: *Options, root: *nodes.AstNode) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);

    var formatter = HtmlFormatter{
        .allocator = allocator,
        .options = options,
        .buffer = &buffer,
    };

    try formatter.format(root, false);
    return buffer.toOwnedSlice();
}

const HtmlFormatter = struct {
    allocator: *mem.Allocator,
    options: *Options,
    buffer: *std.ArrayList(u8),
    last_was_lf: bool = true,

    fn createMap(chars: []const u8) [256]bool {
        var arr = [_]bool{false} ** 256;
        for (chars) |c| {
            arr[c] = true;
        }
        return arr;
    }

    const NEEDS_ESCAPED = createMap("\"&<>");
    const HREF_SAFE = createMap("-_.+!*'(),%#@?=;:/,+&$~abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");

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
                        while (first_tag < ncb.info.?.len and !ctype.isspace(ncb.info.?[first_tag]))
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
            else => {
                std.debug.print("what to do with {}?\n", .{node.data.value});
                unreachable;
            },
        }
        return false;
    }
};

const TestParts = struct {
    allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined,
    options: Options = .{},
    buffer: std.ArrayList(u8) = undefined,
    formatter: HtmlFormatter = undefined,

    fn init(self: *TestParts) void {
        self.allocator = std.heap.GeneralPurposeAllocator(.{}){};
        self.buffer = std.ArrayList(u8).init(&self.allocator.allocator);
        self.formatter = HtmlFormatter{
            .allocator = &self.allocator.allocator,
            .options = &self.options,
            .buffer = &self.buffer,
        };
    }

    fn deinit(self: *TestParts) void {
        self.buffer.deinit();
        _ = self.allocator.deinit();
    }
};

test "escaping works as expected" {
    var testParts = TestParts{};
    testParts.init();
    defer testParts.deinit();

    try testParts.formatter.escape("<hello & goodbye>");
    std.testing.expectEqualStrings("&lt;hello &amp; goodbye&gt;", testParts.buffer.items);
}
