const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.array_list.Managed;
const assert = std.debug.assert;

const clap = @import("clap");
const koino = @import("./koino.zig");

const Parser = koino.parser.Parser;
const Options = koino.Options;
const nodes = koino.nodes;
const html = koino.html;
const MAX_BUFFER_SIZE = 64 * 1024;

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
    var args = try parseArgs(&options, allocator);
    var parser = try Parser.init(allocator, options);

    if (args.positionals[0]) |pos| {
        const markdown = try std.fs.cwd().readFileAlloc(allocator, pos, MAX_BUFFER_SIZE);
        defer allocator.free(markdown);
        try parser.feed(markdown);
    } else {
        var stdin_buf: [MAX_BUFFER_SIZE]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buf);
        var alloc_writer = std.Io.Writer.Allocating.init(allocator);
        errdefer alloc_writer.deinit();

        _ = try stdin_reader.interface.streamRemaining(&alloc_writer.writer);
        const markdown = alloc_writer.written();
        defer allocator.free(markdown);
        try parser.feed(markdown);
    }

    var doc = try parser.finish();
    const output = blk: {
        var arr = ArrayList(u8).init(allocator);
        errdefer arr.deinit();
        try html.print(arr.writer(), allocator, options, doc);
        break :blk try arr.toOwnedSlice();
    };
    defer allocator.free(output);

    if (builtin.mode == .Debug) {
        args.deinit();
        parser.deinit();
        doc.deinit();
    }

    var buf: [MAX_BUFFER_SIZE]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    try stdout_writer.interface.writeAll(output);
    try stdout_writer.interface.flush();
}

const params = clap.parseParamsComptime("-h, --help                 Display this help and exit\n" ++
    "-u, --unsafe               Render raw HTML and dangerous URLs\n" ++
    "-e, --extension <str>...   Enable an extension (" ++ extensionsFriendly ++ ")\n" ++
    "    --header-anchors       Generate anchors for headers\n" ++
    "    --smart                Use smart punctuation\n" ++
    "<str>");

const ClapResult = clap.Result(clap.Help, &params, clap.parsers.default);

fn parseArgs(options: *Options, allocator: std.mem.Allocator) !ClapResult {
    var stderr_buf: [1024]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&stderr_buf);

    const res = try clap.parse(clap.Help, &params, clap.parsers.default, .{ .allocator = allocator });

    if (res.args.help != 0) {
        try stderr.interface.writeAll("Usage: koino ");
        try clap.usage(&stderr.interface, clap.Help, &params);
        try stderr.interface.writeAll("\n\nOptions:\n");
        try clap.help(&stderr.interface, clap.Help, &params, .{});
        std.process.exit(0);
    }

    options.* = .{};
    if (res.args.unsafe != 0)
        options.render.unsafe = true;
    if (res.args.smart != 0)
        options.parse.smart = true;
    if (res.args.@"header-anchors" != 0)
        options.render.header_anchors = true;

    for (res.args.extension) |extension|
        try enableExtension(extension, options);

    return res;
}

const extensions = blk: {
    var exts: []const []const u8 = &[_][]const u8{};
    for (@typeInfo(Options.Extensions).@"struct".fields) |field| {
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
    std.log.err("unknown extension: {s}\n", .{extension});
    std.process.exit(1);
}

/// Uses a GeneralPurposeAllocator for scratch work instead of an ArenaAllocator to aid in locating memory leaks.
/// Result HTML is allocated by std.testing.allocator.
pub fn testMarkdownToHtml(options: Options, markdown: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var doc = try koino.parse(gpa.allocator(), markdown, options);
    defer doc.deinit();

    var result = ArrayList(u8).init(std.testing.allocator);
    errdefer result.deinit();
    try html.print(result.writer(), gpa.allocator(), options, doc);
    return result.toOwnedSlice();
}

test {
    std.testing.refAllDecls(@This());
}
