const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const clap = @import("clap");
const koino = @import("./koino.zig");

const Parser = koino.parser.Parser;
const Options = koino.Options;
const nodes = koino.nodes;
const html = koino.html;

pub fn main() !void {
    // In debug, use the GeneralPurposeAllocator as the Parser internal allocator
    // to shake out memory issues.  There should be no leaks in normal operation.
    // In release, use an arena and reset it at the end.
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var arena: std.heap.ArenaAllocator = undefined;

    var allocator: std.mem.Allocator = undefined;

    if (builtin.mode == .Debug) {
        gpa = std.heap.GeneralPurposeAllocator(.{}){};
        allocator = gpa.allocator();
    } else {
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        allocator = arena.allocator();
    }

    defer {
        if (builtin.mode == .Debug) {
            _ = gpa.deinit();
        } else {
            arena.deinit();
        }
    }

    var options: Options = undefined;
    var args = try parseArgs(&options);
    var parser = try Parser.init(allocator, options);

    if (args.positionals.len > 0) {
        for (args.positionals) |pos| {
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
    var output = blk: {
        var arr = std.ArrayList(u8).init(allocator);
        errdefer arr.deinit();
        try html.print(arr.writer(), allocator, options, doc);
        break :blk arr.toOwnedSlice();
    };
    defer allocator.free(output);

    if (builtin.mode == .Debug) {
        args.deinit();
        parser.deinit();
        doc.deinit();
    }

    try std.io.getStdOut().writer().writeAll(output);
}

const params = params: {
    @setEvalBranchQuota(2000);
    break :params [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help                 Display this help and exit") catch unreachable,
        clap.parseParam("-u, --unsafe               Render raw HTML and dangerous URLs") catch unreachable,
        clap.parseParam("-e, --extension <str>...   Enable an extension (" ++ extensionsFriendly ++ ")") catch unreachable,
        clap.parseParam("    --header-anchors       Generate anchors for headers") catch unreachable,
        clap.parseParam("    --smart                Use smart punctuation") catch unreachable,
        clap.parseParam("<str>") catch unreachable,
    };
};

const ClapResult = clap.Result(clap.Help, &params, clap.parsers.default);

fn parseArgs(options: *Options) !ClapResult {
    var stderr = std.io.getStdErr().writer();

    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{});

    if (res.args.help) {
        try stderr.writeAll("Usage: koino ");
        try clap.usage(stderr, clap.Help, &params);
        try stderr.writeAll("\n\nOptions:\n");
        try clap.help(stderr, clap.Help, &params, .{});
        std.os.exit(0);
    }

    options.* = .{};
    if (res.args.unsafe)
        options.render.unsafe = true;
    if (res.args.smart)
        options.parse.smart = true;
    if (res.args.@"header-anchors")
        options.render.header_anchors = true;

    for (res.args.extension) |extension|
        try enableExtension(extension, options);

    return res;
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
    try std.fmt.format(std.io.getStdErr().writer(), "unknown extension: {s}\n", .{extension});
    std.os.exit(1);
}

/// Performs work using internalAllocator, and writes the result to a Writer.
fn markdownToHtmlInternal(writer: anytype, internalAllocator: std.mem.Allocator, options: Options, markdown: []const u8) !void {
    var doc = try parse(internalAllocator, options, markdown);
    defer doc.deinit();

    try html.print(writer, internalAllocator, options, doc);
}

/// Parses Markdown into an AST.  Use `deinit()' on the returned document to free memory.
pub fn parse(internalAllocator: std.mem.Allocator, options: Options, markdown: []const u8) !*nodes.AstNode {
    var p = try Parser.init(internalAllocator, options);
    defer p.deinit();
    try p.feed(markdown);
    return try p.finish();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and allocates the result HTML with resultAllocator.
pub fn markdownToHtml(resultAllocator: std.mem.Allocator, options: Options, markdown: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(resultAllocator);
    errdefer result.deinit();
    try markdownToHtmlWriter(result.writer(), options, markdown);
    return result.toOwnedSlice();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and writes the result to a Writer.
pub fn markdownToHtmlWriter(writer: anytype, options: Options, markdown: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try markdownToHtmlInternal(writer, arena.allocator(), options, markdown);
}

/// Uses a GeneralPurposeAllocator for scratch work instead of an ArenaAllocator to aid in locating memory leaks.
/// Result HTML is allocated by std.testing.allocator.
pub fn testMarkdownToHtml(options: Options, markdown: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var doc = try parse(gpa.allocator(), options, markdown);
    defer doc.deinit();

    var result = std.ArrayList(u8).init(std.testing.allocator);
    errdefer result.deinit();
    try html.print(result.writer(), gpa.allocator(), options, doc);
    return result.toOwnedSlice();
}

test {
    std.testing.refAllDecls(@This());
}
