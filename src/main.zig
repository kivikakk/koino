const std = @import("std");
const assert = std.debug.assert;

const Parser = @import("parser.zig").Parser;
const nodes = @import("nodes.zig");
const html = @import("html.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var markdown = try std.io.getStdIn().reader().readAllAlloc(&gpa.allocator, 1024 * 1024 * 1024);
    defer gpa.allocator.free(markdown);

    var output = try markdownToHtml(&gpa.allocator, markdown);
    defer gpa.allocator.free(output);

    try std.io.getStdOut().writer().writeAll(output);
}

fn markdownToHtml(allocator: *std.mem.Allocator, markdown: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var root = try nodes.AstNode.create(&arena.allocator, .{
        .value = .Document,
        .content = std.ArrayList(u8).init(&arena.allocator),
    });

    var parser = Parser{
        .allocator = &arena.allocator,
        .root = root,
        .current = root,
    };
    try parser.feed(markdown);
    var doc = try parser.finish();
    defer doc.deinit();

    var noisy_env = std.process.getEnvVarOwned(&arena.allocator, "KOINO_NOISY") catch "";
    const noisy = noisy_env.len > 0;
    doc.validate(noisy);

    return try html.print(allocator, doc);
}

test "" {
    std.meta.refAllDecls(@This());
}

test "convert simple emphases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var output = try markdownToHtml(&gpa.allocator, "hello, _world_ __world__ ___world___ *_world_*\n\nthis is `yummy`\n");
    defer gpa.allocator.free(output);

    std.testing.expectEqualStrings("<p>hello, <em>world</em> <strong>world</strong> <em><strong>world</strong></em> <em><strong>world</strong></em>\n<p>this is <code>yummy</code></p>\n", output);
}
