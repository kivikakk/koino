const std = @import("std");
const assert = std.debug.assert;

const clap = @import("clap");

const parser = @import("parser.zig");
const Options = @import("options.zig").Options;
const nodes = @import("nodes.zig");
const html = @import("html.zig");

pub fn main() !void {
    const params = comptime [_]clap.Param(clap.Help){
        try clap.parseParam("-h, --help      Display this help and exit"),
        try clap.parseParam("-u, --unsafe    Render raw HTML and dangerous URLs"),
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try clap.parse(clap.Help, &params, &gpa.allocator);
    defer args.deinit();

    if (args.flag("--help")) {
        var stderr = std.io.getStdErr().writer();
        try stderr.writeAll("Usage: koino ");
        try clap.usage(stderr, &params);
        try stderr.writeAll("\n\nOptions:\n");
        try clap.help(stderr, &params);
        return;
    }

    var markdown = try std.io.getStdIn().reader().readAllAlloc(&gpa.allocator, 1024 * 1024 * 1024);
    defer gpa.allocator.free(markdown);

    var options = Options{};
    if (args.flag("--unsafe"))
        options.render.unsafe = true;

    var output = try markdownToHtml(&gpa.allocator, options, markdown);
    defer gpa.allocator.free(output);

    try std.io.getStdOut().writer().writeAll(output);
}

pub fn markdownToHtml(allocator: *std.mem.Allocator, options: Options, markdown: []const u8) ![]u8 {
    var arena = std.heap.GeneralPurposeAllocator(.{}){}; //.init(allocator);
    defer _ = arena.deinit();

    var root = try nodes.AstNode.create(&arena.allocator, .{
        .value = .Document,
        .content = std.ArrayList(u8).init(&arena.allocator),
    });

    var p = parser.Parser{
        .allocator = &arena.allocator,
        .refmap = std.StringHashMap(parser.Reference).init(&arena.allocator),
        .hack_refmapKeys = std.ArrayList([]u8).init(&arena.allocator),
        .root = root,
        .current = root,
        .options = options,
    };
    try p.feed(markdown);
    var doc = try p.finish();
    p.deinit();

    defer doc.deinit();

    var noisy_env = std.process.getEnvVarOwned(&arena.allocator, "KOINO_NOISY") catch "";
    const noisy = noisy_env.len > 0;
    doc.validate(noisy);

    return try html.print(allocator, &p.options, doc);
}

test "" {
    std.meta.refAllDecls(@This());
}

test "convert simple emphases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var output = try markdownToHtml(&gpa.allocator, .{}, "hello, _world_ __world__ ___world___ *_world_* **_world_** *__world__*\n\nthis is `yummy`\n");
    defer gpa.allocator.free(output);
    std.testing.expectEqualStrings("<p>hello, <em>world</em> <strong>world</strong> <em><strong>world</strong></em> <em><em>world</em></em> <strong><em>world</em></strong> <em><strong>world</strong></em></p>\n<p>this is <code>yummy</code></p>\n", output);
}

test "smart quotes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var output = try markdownToHtml(&gpa.allocator, .{ .parse = .{ .smart = true } }, "\"Hey,\" she said. \"What's 'up'?\"\n");
    defer gpa.allocator.free(output);
    std.testing.expectEqualStrings("<p>“Hey,” she said. “What’s ‘up’?”</p>\n", output);
}
