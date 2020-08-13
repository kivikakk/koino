const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const ast = @import("ast.zig");
const strings = @import("strings.zig");

const MAX_BACKTICKS = 80;

pub const Subject = struct {
    allocator: *mem.Allocator,
    arena: *mem.Allocator,
    delimiter_arena: *mem.Allocator,

    input: []const u8,

    pos: usize = 0,
    last_delimiter: ?Delimiter = null,
    brackets: std.ArrayList(Bracket),
    backticks: [MAX_BACKTICKS + 1]usize = [_]usize{0} ** (MAX_BACKTICKS + 1),
    scanned_for_backticks: bool = false,
    special_chars: [256]bool = [_]bool{false} ** 256,
    skip_chars: [256]bool = [_]bool{false} ** 256,
    smart_chars: [256]bool = [_]bool{false} ** 256,

    pub fn init(allocator: *mem.Allocator, arena: *mem.Allocator, input: []const u8, delimiter_arena: *mem.Allocator) Subject {
        var s = Subject{
            .allocator = allocator,
            .arena = arena,
            .delimiter_arena = delimiter_arena,

            .input = input,
            .brackets = std.ArrayList(Bracket).init(allocator),
        };
        for ([_]u8{ '\n', '\r', '_', '*', '"', '`', '\'', '\\', '&', '<', '[', ']', '!' }) |c| {
            s.special_chars[c] = true;
        }
        for ([_]u8{ '"', '\'', '.', '-' }) |c| {
            s.smart_chars[c] = true;
        }
        return s;
    }

    pub fn parseInline(self: *Subject, node: *ast.AstNode) !bool {
        const c = self.peekChar();
        if (c == null) {
            return false;
        }

        var new_inl: ?*ast.AstNode = null;

        switch (c.?) {
            0 => return false,
            '\n', '\r' => new_inl = self.handleNewLine(),
            '`' => new_inl = self.handleBackticks(),
            '\\' => new_inl = self.handleBackslash(),
            '&' => new_inl = self.handleEntity(),
            '<' => new_inl = self.handlePointyBrace(),
            '*', '_', '\'', '"' => new_inl = self.handleDelim(c.?),
            '-' => new_inl = self.handleHyphen(),
            '.' => new_inl = self.handlePeriod(),
            '[' => {
                unreachable;
                // self.pos += 1;
                // let inl = make_inline(self.arena, NodeValue::Text(b"[".to_vec()));
                // new_inl = Some(inl);
                // self.push_bracket(false, inl);
            },
            ']' => new_inl = self.handleCloseBracket(),
            '!' => {
                unreachable;
                // self.pos += 1;
                // if self.peek_char() == Some(&(b'[')) && self.peek_char_n(1) != Some(&(b'^')) {
                // self.pos += 1;
                // let inl = make_inline(self.arena, NodeValue::Text(b"![".to_vec()));
                // new_inl = Some(inl);
                // self.push_bracket(true, inl);
                // } else {
                // new_inl = Some(make_inline(self.arena, NodeValue::Text(b"!".to_vec())));
                // }
            },
            else => {
                const endpos = self.findSpecialChar();
                var contents = self.input[self.pos..endpos];
                self.pos = endpos;

                if (self.peekChar()) |n| {
                    if (strings.isLineEndChar(n)) {
                        contents = strings.rtrim(contents);
                    }
                }

                var new_contents = std.ArrayList(u8).init(self.allocator);
                try new_contents.appendSlice(contents);
                new_inl = try makeInline(self.arena, self.allocator, .{ .Text = new_contents });
            },
        }

        if (new_inl) |inl| {
            node.append(inl);
        }

        return true;
    }

    pub fn processEmphasis(self: *Subject, stack_bottom: ?Delimiter) void {
        var closer = self.last_delimiter;

        var openers_bottom: [3][128]?Delimiter = [_][128]?Delimiter{[_]?Delimiter{null} ** 128} ** 3;
        for (openers_bottom) |*i| {
            i['*'] = stack_bottom;
            i['_'] = stack_bottom;
            i['\''] = stack_bottom;
            i['"'] = stack_bottom;
        }
    }

    pub fn popBracket(self: *Subject) bool {
        return self.brackets.popOrNull() != null;
    }

    fn peekChar(self: *Subject) ?u8 {
        return self.peekCharN(0);
    }

    fn peekCharN(self: *Subject, n: usize) ?u8 {
        if (self.pos + n >= self.input.len) {
            return null;
        }
        const c = self.input[self.pos + n];
        assert(c > 0);
        return c;
    }

    fn findSpecialChar(self: *Subject) usize {
        var n = self.pos;
        while (n < self.input.len) : (n += 1) {
            if (self.special_chars[self.input[n]]) {
                return n;
            }
            // TODO: smart option
        }
        return n;
    }

    fn handleNewLine(self: *Subject) *ast.AstNode {
        unreachable;
    }

    fn handleBackticks(self: *Subject) *ast.AstNode {
        unreachable;
    }

    fn handleBackslash(self: *Subject) *ast.AstNode {
        unreachable;
    }

    fn handleEntity(self: *Subject) *ast.AstNode {
        unreachable;
    }

    fn handlePointyBrace(self: *Subject) *ast.AstNode {
        unreachable;
    }

    fn handleDelim(self: *Subject, c: u8) *ast.AstNode {
        unreachable;
    }

    fn handleHyphen(self: *Subject) *ast.AstNode {
        unreachable;
    }

    fn handlePeriod(self: *Subject) *ast.AstNode {
        unreachable;
    }

    fn handleCloseBracket(self: *Subject) *ast.AstNode {
        unreachable;
    }
};

const Bracket = struct {};
const Delimiter = struct {};

fn makeInline(arena: *mem.Allocator, allocator: *mem.Allocator, value: ast.NodeValue) !*ast.AstNode {
    return ast.AstNode.create(arena, .{
        .value = value,
        .content = std.ArrayList(u8).init(allocator),
        .open = false,
    });
}
