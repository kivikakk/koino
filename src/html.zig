const std = @import("std");
const p = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

const ast = @import("ast.zig");

pub fn print(root: *ast.AstNode) !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    try f(&allocator.allocator, root, false);
}

fn f(allocator: *mem.Allocator, input_node: *ast.AstNode, plain: bool) !void {
    const Phase = enum { Pre, Post };
    const StackEntry = struct {
        node: *ast.AstNode,
        plain: bool,
        phase: Phase,
    };

    var stack = std.ArrayList(StackEntry).init(allocator);
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
                    new_plain = try fnode(entry.node, true);
                }

                var it = entry.node.reverseChildrenIterator();
                while (it.next()) |ch| {
                    try stack.append(.{ .node = ch, .plain = new_plain, .phase = .Pre });
                }
            },
            .Post => {
                assert(!entry.plain);
                _ = try fnode(entry.node, false);
            },
        }
    }
}

fn fnode(node: *ast.AstNode, entering: bool) !bool {
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
            p("what to do with {}?\n", .{node.data.value});
            unreachable;
        },
    }
    return false;
}

fn cr() void {
    p("\n", .{});
}
