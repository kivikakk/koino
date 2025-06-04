const std = @import("std");

pub const parser = @import("parser.zig");
pub const Options = @import("options.zig").Options;
pub const nodes = @import("nodes.zig");
pub const html = @import("html.zig");

/// Performs work using internalAllocator, and writes the result to a Writer.
fn markdownToHtmlInternal(writer: anytype, internalAllocator: std.mem.Allocator, markdown: []const u8, options: Options) !void {
    var doc = try parse(internalAllocator, markdown, options);
    defer doc.deinit();

    try html.print(writer, internalAllocator, options, doc);
}

/// Parses Markdown into an AST.  Use `deinit()' on the returned document to free memory.
pub fn parse(internalAllocator: std.mem.Allocator, markdown: []const u8, options: Options) !*nodes.AstNode {
    var p = try parser.Parser.init(internalAllocator, options);
    defer p.deinit();
    try p.feed(markdown);
    return try p.finish();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and allocates the result HTML with resultAllocator.
pub fn markdownToHtml(resultAllocator: std.mem.Allocator, markdown: []const u8, options: Options) ![]u8 {
    var result = std.ArrayList(u8).init(resultAllocator);
    errdefer result.deinit();
    try markdownToHtmlWriter(result.writer(), markdown, options);
    return result.toOwnedSlice();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and writes the result to a Writer.
pub fn markdownToHtmlWriter(writer: anytype, markdown: []const u8, options: Options) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try markdownToHtmlInternal(writer, arena.allocator(), markdown, options);
}
