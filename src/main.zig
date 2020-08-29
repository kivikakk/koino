const std = @import("std");
const assert = std.debug.assert;

const clap = @import("clap");

const Parser = @import("parser.zig").Parser;
const Options = @import("options.zig").Options;
const nodes = @import("nodes.zig");
const html = @import("html.zig");

pub fn main() !void {
    // In debug, use the GeneralPurposeAllocator as the Parser internal allocator
    // to shake out memory issues.  There should be no leaks in normal operation.
    // In release, use an arena and reset it at the end.
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var arena: std.heap.ArenaAllocator = undefined;

    var allocator: *std.mem.Allocator = undefined;

    if (std.builtin.mode == .Debug) {
        gpa = std.heap.GeneralPurposeAllocator(.{}){};
        allocator = &gpa.allocator;
    } else {
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        allocator = &arena.allocator;
    }

    defer {
        if (std.builtin.mode == .Debug) {
            _ = gpa.deinit();
        } else {
            arena.deinit();
        }
    }

    var options: Options = undefined;
    var args = try parseArgs(allocator, &options);
    var parser = try Parser.init(allocator, options);

    if (args.positionals().len > 0) {
        for (args.positionals()) |pos| {
            var markdown = try std.fs.cwd().readFileAlloc(allocator, pos, 1024 * 1024 * 1024);
            defer allocator.free(markdown);
            try parser.feed(markdown);
        }
    } else {
        var markdown = try std.io.getStdIn().reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
        defer allocator.free(markdown);
        try parser.feed(markdown);
    }

    var doc = try parser.finish();
    var output = try html.print(allocator, options, doc);
    defer allocator.free(output);

    if (std.builtin.mode == .Debug) {
        args.deinit();
        parser.deinit();
        doc.deinit();
    }

    try std.io.getStdOut().writer().writeAll(output);
}

const params = comptime params: {
    @setEvalBranchQuota(2000);
    break :params [_]clap.Param(clap.Help){
        try clap.parseParam("-h, --help                       Display this help and exit"),
        try clap.parseParam("-u, --unsafe                     Render raw HTML and dangerous URLs"),
        try clap.parseParam("-e, --extension <EXTENSION>...   Enable an extension (" ++ extensionsFriendly ++ ")"),
        try clap.parseParam("    --header-anchors             Generate anchors for headers"),
        try clap.parseParam("    --smart                      Use smart punctuation"),
        clap.Param(clap.Help){
            .takes_value = .One,
        },
    };
};

const Args = clap.Args(clap.Help, &params);

fn parseArgs(allocator: *std.mem.Allocator, options: *Options) !Args {
    var stderr = std.io.getStdErr().writer();

    var args = try clap.parse(clap.Help, &params, allocator);

    if (args.flag("--help")) {
        try stderr.writeAll("Usage: koino ");
        try clap.usage(stderr, &params);
        try stderr.writeAll("\n\nOptions:\n");
        try clap.help(stderr, &params);
        std.os.exit(0);
    }

    options.* = .{};
    if (args.flag("--unsafe"))
        options.render.unsafe = true;
    if (args.flag("--smart"))
        options.parse.smart = true;
    if (args.flag("--header-anchors"))
        options.render.header_anchors = true;

    for (args.options("--extension")) |extension|
        try enableExtension(extension, options);

    return args;
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

/// Performs work using internalAllocator, and allocates the result HTML with resultAllocator.
fn markdownToHtmlInternal(resultAllocator: *std.mem.Allocator, internalAllocator: *std.mem.Allocator, options: Options, markdown: []const u8) ![]u8 {
    var doc = try parse(internalAllocator, options, markdown);
    defer doc.deinit();

    return try html.print(resultAllocator, options, doc);
}

/// Parses Markdown into an AST.  Use `deinit()' on the returned document to free memory.
pub fn parse(internalAllocator: *std.mem.Allocator, options: Options, markdown: []const u8) !*nodes.AstNode {
    var p = try Parser.init(internalAllocator, options);
    defer p.deinit();
    try p.feed(markdown);
    return try p.finish();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and allocates the result HTML with resultAllocator.
pub fn markdownToHtml(resultAllocator: *std.mem.Allocator, options: Options, markdown: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    return markdownToHtmlInternal(resultAllocator, &arena.allocator, options, markdown);
}

/// Uses a GeneralPurposeAllocator for scratch work instead of an ArenaAllocator to aid in locating memory leaks.
/// Result HTML is allocated by std.testing.allocator.
pub fn testMarkdownToHtml(options: Options, markdown: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    return markdownToHtmlInternal(std.testing.allocator, &gpa.allocator, options, markdown);
}

test "" {
    std.meta.refAllDecls(@This());
}
