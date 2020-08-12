const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const strings = @import("strings.zig");
const ast = @import("ast.zig");

const Parser = struct {
    allocator: *std.mem.Allocator,
    arena: *std.mem.Allocator,
    root: *ast.Ast(ast.Node),
    current: *ast.Ast(ast.Node),
    line_number: u32,
    offset: usize,
    column: usize,
    first_nonspace: usize,
    first_nonspace_column: usize,
    indent: usize,
    blank: bool,
    partially_consumed_tab: bool,
    last_line_length: usize,

    fn feed(self: Parser, s: []const u8) !void {
        var i: usize = 0;
        var sz = s.len;
        var linebuf = std.ArrayList(u8).init(self.allocator);
        defer linebuf.deinit();

        while (i < sz) {
            var process = true;
            var eol = i;
            while (eol < sz) {
                if (strings.isLineEndChar(s[eol])) {
                    break;
                }
                if (s[eol] == 0) {
                    process = false;
                    break;
                }
                eol += 1;
            }

            if (process) {
                if (linebuf.items.len != 0) {
                    try linebuf.appendSlice(s[i..eol]);
                    try self.processLine(linebuf.span());
                    linebuf.items.len = 0;
                } else if (sz > eol and s[eol] == '\n') {
                    try self.processLine(s[i .. eol + 1]);
                } else {
                    try self.processLine(s[i..eol]);
                }

                i = eol;
                if (i < sz and s[i] == '\r') {
                    i += 1;
                }
                if (i < sz and s[i] == '\n') {
                    i += 1;
                }
            } else {
                assert(eol < sz and s[eol] == 0);
                try linebuf.appendSlice(s[i..eol]);
                try linebuf.appendSlice("\u{fffd}");
                i = eol + 1;
            }
        }
    }

    fn processLine(self: Parser, s: []const u8) !void {
        print("processLine: {}\n", .{s});
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var root = ast.Ast(ast.Node){
        .content = .{
            .value = .Document,
            .content = "",
            .start_line = 0,
            .open = true,
            .last_line_blank = false,
        },
    };

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};

    const parser = Parser{
        .allocator = &allocator.allocator,
        .arena = &arena.allocator,
        .root = &root,
        .current = &root,
        .line_number = 0,
        .offset = 0,
        .column = 0,
        .first_nonspace = 0,
        .first_nonspace_column = 0,
        .indent = 0,
        .blank = false,
        .partially_consumed_tab = false,
        .last_line_length = 0,
    };
    try parser.feed("hello, world!\n\nthis is **yummy**!\n");
}
