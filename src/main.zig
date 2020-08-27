const std = @import("std");
const assert = std.debug.assert;

const clap = @import("clap");

const parser = @import("parser.zig");
const Options = @import("options.zig").Options;
const nodes = @import("nodes.zig");
const html = @import("html.zig");

pub fn main() !void {
    @setEvalBranchQuota(2000);

    var stderr = std.io.getStdErr().writer();

    const params = comptime [_]clap.Param(clap.Help){
        try clap.parseParam("-h, --help                       Display this help and exit"),
        try clap.parseParam("-u, --unsafe                     Render raw HTML and dangerous URLs"),
        try clap.parseParam("-e, --extension <EXTENSION>...   Enable an extension (" ++ extensionsFriendly ++ ")"),
        try clap.parseParam("    --header-anchors             Generate anchors for headers"),
        try clap.parseParam("    --smart                      Use smart punctuation"),
        clap.Param(clap.Help){
            .takes_value = .One,
        },
    };

    var allocator: *std.mem.Allocator = undefined;
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){};
    var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    if (std.builtin.mode == .Debug) {
        allocator = &gpa.allocator;
    } else {
        allocator = &arena.allocator;
    }

    defer {
        if (std.builtin.mode == .Debug) {
            _ = gpa.deinit();
        }
    }

    var args = try clap.parse(clap.Help, &params, allocator);
    defer args.deinit();

    if (args.flag("--help")) {
        try stderr.writeAll("Usage: koino ");
        try clap.usage(stderr, &params);
        try stderr.writeAll("\n\nOptions:\n");
        try clap.help(stderr, &params);
        return;
    }

    var options = Options{};
    if (args.flag("--unsafe"))
        options.render.unsafe = true;
    if (args.flag("--smart"))
        options.parse.smart = true;
    if (args.flag("--header-anchors"))
        options.render.header_anchors = true;

    for (args.options("--extension")) |extension|
        try enableExtension(extension, &options);

    var p = try parser.Parser.init(&arena.allocator, options);

    if (args.positionals().len > 0) {
        for (args.positionals()) |pos| {
            var markdown = try std.fs.cwd().readFileAlloc(allocator, pos, 1024 * 1024 * 1024);
            defer allocator.free(markdown);
            try p.feed(markdown);
        }
    } else {
        var markdown = try std.io.getStdIn().reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
        defer allocator.free(markdown);
        try p.feed(markdown);
    }

    var doc = try p.finish();

    var output = try html.print(allocator, &p.options, doc);
    defer allocator.free(output);

    if (std.builtin.mode == .Debug) {
        p.deinit();
        doc.deinit();
    }

    try std.io.getStdOut().writer().writeAll(output);
}

const extensions = blk: {
    var exts: []const []const u8 = &[_][]const u8{};
    for (@typeInfo(Options.Extensions).Struct.fields) |field| {
        exts = exts ++ [_][]const u8{field.name};
    }
    break :blk exts;
};

const extensionsFriendly = blk: {
    var extsFriendly: []const u8 = &[_]u8{};
    var first = true;
    for (extensions) |extension| {
        if (first) {
            first = false;
        } else {
            extsFriendly = extsFriendly ++ ",";
        }
        extsFriendly = extsFriendly ++ extension;
    }
    break :blk extsFriendly;
};

fn enableExtension(extension: []const u8, options: *Options) !void {
    inline for (extensions) |valid_extension| {
        if (std.mem.eql(u8, valid_extension, extension)) {
            @field(options.extensions, valid_extension) = true;
            return;
        }
    }
    try std.fmt.format(std.io.getStdErr().writer(), "unknown extension: {}\n", .{extension});
    std.os.exit(1);
}

fn markdownToHtmlInternal(resultAllocator: *std.mem.Allocator, internalAllocator: *std.mem.Allocator, options: Options, markdown: []const u8) ![]u8 {
    var p = try parser.Parser.init(internalAllocator, options);
    try p.feed(markdown);
    var doc = try p.finish();
    p.deinit();

    defer doc.deinit();

    return try html.print(resultAllocator, p.options, doc);
}

pub fn markdownToHtml(resultAllocator: *std.mem.Allocator, options: Options, markdown: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    return markdownToHtmlInternal(resultAllocator, &arena.allocator, options, markdown);
}

/// Uses a GeneralPurposeAllocator for scratch work instead of an ArenaAllocator
/// to aid in locating memory leaks.  Returned memory is allocated by std.testing.allocator
/// and must be freed by the caller
pub fn testMarkdownToHtml(options: Options, markdown: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    return markdownToHtmlInternal(std.testing.allocator, &gpa.allocator, options, markdown);
}

test "" {
    std.meta.refAllDecls(@This());
}
