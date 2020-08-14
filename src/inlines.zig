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
    last_delimiter: ?*Delimiter = null,
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
            '`' => new_inl = try self.handleBackticks(),
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

    pub fn processEmphasis(self: *Subject, stack_bottom: ?*Delimiter) void {
        var closer = self.last_delimiter;

        var openers_bottom: [3][128]?*Delimiter = [_][128]?*Delimiter{[_]?*Delimiter{null} ** 128} ** 3;
        for (openers_bottom) |*i| {
            i['*'] = stack_bottom;
            i['_'] = stack_bottom;
            i['\''] = stack_bottom;
            i['"'] = stack_bottom;
        }

        while (closer != null and closer.?.prev != stack_bottom) {
            closer = closer.?.prev;
        }

        while (closer) |closer_| {
            unreachable;
        }

        while (self.last_delimiter != null and self.last_delimiter != stack_bottom) {
            self.removeDelimiter(self.last_delimiter.?);
        }
    }

    fn removeDelimiter(self: *Subject, delimiter: *Delimiter) void {
        if (delimiter.next == null) {
            assert(delimiter == self.last_delimiter.?);
            self.last_delimiter = delimiter.prev;
        } else {
            delimiter.next.?.prev = delimiter.prev;
        }
        if (delimiter.prev != null) {
            delimiter.prev.?.next = delimiter.next;
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

    fn takeWhile(self: *Subject, c: u8) usize {
        const start_pos = self.pos;
        while (self.peekChar() == c) {
            self.pos += 1;
        }
        return self.pos - start_pos;
    }

    fn scanToClosingBacktick(self: *Subject, openticklength: usize) ?usize {
        if (openticklength > MAX_BACKTICKS) {
            return null;
        }

        if (self.scanned_for_backticks and self.backticks[openticklength] <= self.pos) {
            return null;
        }

        while (true) {
            var peeked = self.peekChar();
            while (peeked != null and peeked.? != '`') {
                self.pos += 1;
                peeked = self.peekChar();
            }
            if (self.pos >= self.input.len) {
                self.scanned_for_backticks = true;
                return null;
            }
            const numticks = self.takeWhile('`');
            if (numticks <= MAX_BACKTICKS) {
                self.backticks[numticks] = self.pos - numticks;
            }
            if (numticks == openticklength) {
                return self.pos;
            }
        }
    }

    fn handleBackticks(self: *Subject) !*ast.AstNode {
        const openticks = self.takeWhile('`');
        const startpos = self.pos;
        const endpos = self.scanToClosingBacktick(openticks);

        if (endpos) |end| {
            const buf = self.input[startpos .. end - openticks];
            var code = std.ArrayList(u8).init(self.allocator);
            try strings.normalizeCode(buf, &code);
            return try makeInline(self.arena, self.allocator, .{ .Code = code });
        } else {
            self.pos = startpos;
            var new_contents = std.ArrayList(u8).init(self.allocator);
            try new_contents.appendNTimes('`', openticks);
            return try makeInline(self.arena, self.allocator, .{ .Text = new_contents });
        }
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

const Delimiter = struct {
    inl: *ast.AstNode,
    length: usize,
    delim_char: u8,
    can_open: bool,
    can_close: bool,
    prev: ?*Delimiter,
    next: ?*Delimiter,
};

const Bracket = struct {
    previous_delimiter: ?*Delimiter,
    inl_text: *ast.AstNode,
    position: usize,
    image: bool,
    active: bool,
    bracket_after: bool,
};

fn makeInline(arena: *mem.Allocator, allocator: *mem.Allocator, value: ast.NodeValue) !*ast.AstNode {
    return ast.AstNode.create(arena, .{
        .value = value,
        .content = std.ArrayList(u8).init(allocator),
    });
}
