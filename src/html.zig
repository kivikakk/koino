const std = @import("std");
const p = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

const ast = @import("ast.zig");

pub fn print(out: anytype, root: *ast.AstNode) !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = allocator.deinit();

    var formatter = HtmlFormatter(@TypeOf(out)){
        .allocator = &allocator.allocator,
        .writer = WriteWithLast(@TypeOf(out)){
            .context = WriteWithLastContext(@TypeOf(out)){
                .writer = out,
                .last_was_lf = false,
            },
        },
    };

    try formatter.format(out, root, false);
}

fn WriteWithLastContext(comptime writer: type) type {
    return struct {
        writer: writer,
        last_was_lf: bool,
    };
}

fn WriteWithLast(comptime writer: type) type {
    return std.io.Writer(WriteWithLastContext(writer), anyerror, writeWithLast);
}

// TODO
fn writeWithLast(wasLast: *bool, bytes: []const u8) anyerror!usize {}

fn HtmlFormatter(comptime writer: type) type {
    return struct {
        allocator: *mem.Allocator,
        writer: WriteWithLast(writer),

        fn format(self: *HtmlFormatter, out: anytype, input_node: *ast.AstNode, plain: bool) !void {
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
                            new_plain = try self.fnode(out, entry.node, true);
                        }

                        var it = entry.node.reverseChildrenIterator();
                        while (it.next()) |ch| {
                            try stack.append(.{ .node = ch, .plain = new_plain, .phase = .Pre });
                        }
                    },
                    .Post => {
                        assert(!entry.plain);
                        _ = try self.fnode(out, entry.node, false);
                    },
                }
            }
        }

        fn fnode(self: *HtmlFormatter, out: anytype, node: *ast.AstNode, entering: bool) !bool {
            switch (node.data.value) {
                .Document => {},
                .BlockQuote => {
                    if (entering) {
                        cr();
                        p("<blockquote>\n", .{});
                    } else {
                        cr();
                        p("</blockquote>", .{});
                    }
                },
                .Paragraph => {
                    if (entering) {
                        p("<p>\n", .{});
                    } else {
                        p("</p>\n", .{});
                    }
                },
                .Text => |literal| {
                    if (entering) {
                        p("{}", .{literal.span()});
                    }
                },
                else => {
                    // out("what to do with {}?\n", .{node.data.value});
                    unreachable;
                },
            }
            return false;
        }

        fn cr() void {
            p("\n", .{});
        }
    };
}
