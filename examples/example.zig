const std = @import("std");
const assert = std.debug.assert;

const koino = @import("test_koino");

const markdown = @embedFile("./cc-&-gfm.md");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const options = koino.Options{
        .extensions = .{
            .table = true,
            .autolink = true,
            .strikethrough = true,
        },
    };

    var p = try koino.parser.Parser.init(arena.allocator(), options);
    try p.feed(markdown);

    var doc = try p.finish();
    p.deinit();

    defer doc.deinit();

    var buffer = std.array_list.Managed(u8).init(allocator);
    defer buffer.clearAndFree();
    try koino.html.print(buffer.writer(), allocator, p.options, doc);
    std.debug.print("{s}\n", .{buffer.items});
}
