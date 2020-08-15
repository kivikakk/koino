const std = @import("std");

const parser = @import("parser.zig");
const ast = @import("ast.zig");
const html = @import("html.zig");

pub fn main() anyerror!void {
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator.deinit();

    var root = try ast.AstNode.create(&allocator.allocator, .{
        .value = .Document,
        .content = std.ArrayList(u8).init(&allocator.allocator),
    });

    var p = parser.Parser{
        .allocator = &allocator.allocator,
        .root = root,
        .current = root,
    };
    try p.feed("hello, _world_ __world__ ___world___ *_world_*\n\nthis is `yummy`\n");
    var doc = try p.finish();

    var noisy_env = std.process.getEnvVarOwned(&allocator.allocator, "KOINO_NOISY") catch "";
    const noisy = noisy_env.len > 0;
    doc.validate(noisy);

    var buffer = try html.print(&allocator.allocator, doc);
    defer buffer.deinit();

    doc.deinit();

    try std.io.getStdOut().outStream().writeAll(buffer.span());
}

test "" {
    std.meta.refAllDecls(@This());
}
