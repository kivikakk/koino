const std = @import("std");
const p = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

const ast = @import("ast.zig");

pub fn print(allocator: *mem.Allocator, root: *ast.AstNode) !std.ArrayList(u8) {
    var buffer = std.ArrayList(u8).init(allocator);

    var formatter = HtmlFormatter{
        .allocator = allocator,
        .buffer = &buffer,
    };

    try formatter.format(root, false);
    return buffer;
}

const HtmlFormatter = struct {
    allocator: *mem.Allocator,
    buffer: *std.ArrayList(u8),
    last_was_lf: bool = false,

    fn createMap(chars: []const u8) [256]bool {
        var arr = [_]bool{false} ** 256;
        for (chars) |c| {
            arr[c] = true;
        }
        return arr;
    }

    const NEEDS_ESCAPED = createMap("\"&<>");
    const HREF_SAFE = createMap("-_.+!*'(),%#@?=;:/,+&$~abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");

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

    fn writeAll(self: *HtmlFormatter, s: []const u8) !void {
        if (s.len == 0) {
            return;
        }
        try self.buffer.appendSlice(s);
        self.last_was_lf = s[s.len - 1] == '\n';
    }

    fn format(self: *HtmlFormatter, input_node: *ast.AstNode, plain: bool) !void {
        const Phase = enum { Pre, Post };
        const StackEntry = struct {
            node: *ast.AstNode,
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
                        unreachable;
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

    fn fnode(self: *HtmlFormatter, node: *ast.AstNode, entering: bool) !bool {
        switch (node.data.value) {
            .Document => {},
            .BlockQuote => {
                if (entering) {
                    try self.cr();
                    try self.writeAll("<blockquote>\n");
                } else {
                    try self.cr();
                    try self.writeAll("</blockquote>\n");
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
                    try self.escape(literal.span());
                }
            },
            else => {
                // out("what to do with {}?\n", .{node.data.value});
                unreachable;
            },
        }
        return false;
    }
};

test "escaping works as expected" {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = allocator.deinit();

    var buffer = std.ArrayList(u8).init(&allocator.allocator);
    defer buffer.deinit();

    var formatter = HtmlFormatter{
        .allocator = &allocator.allocator,
        .buffer = &buffer,
    };

    try formatter.escape("<hello & goodbye>");

    assert(mem.eql(u8, buffer.span(), "&lt;hello &amp; goodbye&gt;"));
}
