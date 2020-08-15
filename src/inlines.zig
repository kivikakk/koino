const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const nodes = @import("nodes.zig");
const strings = @import("strings.zig");
const unicode = @import("unicode.zig");
const Options = @import("options.zig").Options;

const MAX_BACKTICKS = 80;

pub const Subject = struct {
    allocator: *mem.Allocator,
    options: *Options,
    input: []const u8,
    pos: usize = 0,
    last_delimiter: ?*Delimiter = null,
    brackets: std.ArrayList(Bracket),
    backticks: [MAX_BACKTICKS + 1]usize = [_]usize{0} ** (MAX_BACKTICKS + 1),
    scanned_for_backticks: bool = false,
    special_chars: [256]bool = [_]bool{false} ** 256,
    skip_chars: [256]bool = [_]bool{false} ** 256,
    smart_chars: [256]bool = [_]bool{false} ** 256,

    pub fn init(allocator: *mem.Allocator, options: *Options, input: []const u8) Subject {
        var s = Subject{
            .allocator = allocator,
            .options = options,
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

    pub fn parseInline(self: *Subject, node: *nodes.AstNode) !bool {
        const c = self.peekChar();
        if (c == null) {
            return false;
        }

        var new_inl: ?*nodes.AstNode = null;

        switch (c.?) {
            0 => return false,
            '\n', '\r' => new_inl = try self.handleNewLine(),
            '`' => new_inl = try self.handleBackticks(),
            '\\' => new_inl = self.handleBackslash(),
            '&' => new_inl = self.handleEntity(),
            '<' => new_inl = self.handlePointyBrace(),
            '*', '_', '\'', '"' => new_inl = try self.handleDelim(c.?),
            '-' => new_inl = self.handleHyphen(),
            '.' => new_inl = try self.handlePeriod(),
            '[' => {
                unreachable;
                // self.pos += 1;
                // let inl = make_inline(self.allocator, NodeValue::Text(b"[".to_vec()));
                // new_inl = Some(inl);
                // self.push_bracket(false, inl);
            },
            ']' => new_inl = self.handleCloseBracket(),
            '!' => {
                unreachable;
                // self.pos += 1;
                // if self.peek_char() == Some(&(b'[')) && self.peek_char_n(1) != Some(&(b'^')) {
                // self.pos += 1;
                // let inl = make_inline(self.allocator, NodeValue::Text(b"![".to_vec()));
                // new_inl = Some(inl);
                // self.push_bracket(true, inl);
                // } else {
                // new_inl = Some(make_inline(self.allocator, NodeValue::Text(b"!".to_vec())));
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
                new_inl = try self.makeInline(.{ .Text = new_contents });
            },
        }

        if (new_inl) |inl| {
            node.append(inl);
        }

        return true;
    }

    fn makeInline(self: *Subject, value: nodes.NodeValue) !*nodes.AstNode {
        return nodes.AstNode.create(self.allocator, .{
            .value = value,
            .content = std.ArrayList(u8).init(self.allocator),
        });
    }

    pub fn processEmphasis(self: *Subject, stack_bottom: ?*Delimiter) !void {
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

        while (closer != null) {
            if (closer.?.can_close) {
                var opener = closer.?.prev;
                var opener_found = false;

                while (opener != null and opener != openers_bottom[closer.?.length % 3][closer.?.delim_char]) {
                    if (opener.?.can_open and opener.?.delim_char == closer.?.delim_char) {
                        const odd_match = (closer.?.can_open or opener.?.can_close) and ((opener.?.length + closer.?.length) % 3 == 0) and !(opener.?.length % 3 == 0 and closer.?.length % 3 == 0);
                        if (!odd_match) {
                            opener_found = true;
                            break;
                        }
                    }
                    opener = opener.?.prev;
                }

                var old_closer = closer;

                if (opener.?.delim_char == '*' or closer.?.delim_char == '_') {
                    if (opener_found) {
                        closer = try self.insertEmph(opener.?, closer.?);
                    } else {
                        closer = closer.?.next;
                    }
                } else if (closer.?.delim_char == '\'') {
                    unreachable;
                } else if (closer.?.delim_char == '"') {
                    unreachable;
                }

                if (!opener_found) {
                    const ix = old_closer.?.length % 3;
                    openers_bottom[ix][old_closer.?.delim_char] =
                        old_closer.?.prev;

                    if (!old_closer.?.can_open) {
                        self.removeDelimiter(old_closer.?);
                    }
                }
            } else {
                closer = closer.?.next;
            }
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

    fn eof(self: *Subject) bool {
        return self.pos >= self.input.len;
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
            if (self.special_chars[self.input[n]])
                return n;
            if (self.options.parse.smart and self.smart_chars[self.input[n]])
                return n;
        }
        return n;
    }

    fn handleNewLine(self: *Subject) !*nodes.AstNode {
        const nlpos = self.pos;
        if (self.input[self.pos] == '\r') self.pos += 1;
        if (self.input[self.pos] == '\n') self.pos += 1;
        self.skipSpaces();
        const line_break = nlpos > 1 and self.input[nlpos - 1] == ' ' and self.input[nlpos - 2] == ' ';
        return self.makeInline(if (line_break) .LineBreak else .SoftBreak);
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

    fn handleBackticks(self: *Subject) !*nodes.AstNode {
        const openticks = self.takeWhile('`');
        const startpos = self.pos;
        const endpos = self.scanToClosingBacktick(openticks);

        if (endpos) |end| {
            const buf = self.input[startpos .. end - openticks];
            var code = try strings.normalizeCode(self.allocator, buf);
            return try self.makeInline(.{ .Code = code });
        } else {
            self.pos = startpos;
            var new_contents = std.ArrayList(u8).init(self.allocator);
            try new_contents.appendNTimes('`', openticks);
            return try self.makeInline(.{ .Text = new_contents });
        }
    }

    fn skipSpaces(self: *Subject) void {
        while (self.peekChar()) |c| {
            if (!(c == ' ' or c == '\t'))
                break;
            self.pos += 1;
        }
    }

    fn handleBackslash(self: *Subject) *nodes.AstNode {
        unreachable;
    }

    fn handleEntity(self: *Subject) *nodes.AstNode {
        unreachable;
    }

    fn handlePointyBrace(self: *Subject) *nodes.AstNode {
        unreachable;
    }

    fn handleDelim(self: *Subject, c: u8) !*nodes.AstNode {
        const scan = try self.scanDelims(c);
        const contents = if (c == '\'' and self.options.parse.smart)
            "’"
        else if (c == '"' and self.options.parse.smart and scan.can_close)
            "”"
        else if (c == '"' and self.options.parse.smart and !scan.can_close)
            "“"
        else
            self.input[self.pos - scan.num_delims .. self.pos];
        var text = std.ArrayList(u8).init(self.allocator);
        try text.appendSlice(contents);
        const inl = try self.makeInline(.{ .Text = text });

        if ((scan.can_open or scan.can_close) and (!(c == '\'' or c == '"') or self.options.parse.smart)) {
            try self.pushDelimiter(c, scan.can_open, scan.can_close, inl);
        }

        return inl;
    }

    fn handleHyphen(self: *Subject) *nodes.AstNode {
        unreachable;
    }

    fn handlePeriod(self: *Subject) !*nodes.AstNode {
        self.pos += 1;
        var text = std.ArrayList(u8).init(self.allocator);
        // Weird `if` nesting due to https://github.com/ziglang/zig/issues/6059.
        if (self.options.parse.smart) {
            if (self.peekChar() == @as(u8, '.')) {
                self.pos += 1;
                if (self.peekChar() == @as(u8, '.')) {
                    self.pos += 1;
                    try text.appendSlice("…");
                } else {
                    try text.appendSlice("..");
                }
            } else {
                try text.appendSlice(".");
            }
        } else {
            try text.appendSlice(".");
        }
        return try self.makeInline(.{ .Text = text });
    }

    const ScanResult = struct {
        num_delims: usize,
        can_open: bool,
        can_close: bool,
    };

    fn scanDelims(self: *Subject, c: u8) !ScanResult {
        var before_char: u21 = '\n';
        if (self.pos > 0) {
            var before_char_pos = self.pos - 1;
            while (before_char_pos > 0 and (self.input[before_char_pos] >> 6 == 2 or self.skip_chars[self.input[before_char_pos]])) {
                before_char_pos -= 1;
            }
            var utf8 = (try std.unicode.Utf8View.init(self.input[before_char_pos..self.pos])).iterator();
            if (utf8.nextCodepoint()) |codepoint| {
                if (codepoint >= 256 or !self.skip_chars[codepoint]) {
                    before_char = codepoint;
                }
            }
        }

        var num_delims: usize = 0;
        if (c == '\'' or c == '"') {
            num_delims += 1;
            self.pos += 1;
        } else while (self.peekChar() == c) {
            num_delims += 1;
            self.pos += 1;
        }

        var after_char: u21 = '\n';
        if (!self.eof()) {
            var after_char_pos = self.pos;
            while (after_char_pos < self.input.len - 1 and self.skip_chars[self.input[after_char_pos]]) {
                after_char_pos += 1;
            }
            var utf8 = (try std.unicode.Utf8View.init(self.input[after_char_pos..])).iterator();
            if (utf8.nextCodepoint()) |codepoint| {
                if (codepoint >= 256 or !self.skip_chars[codepoint]) {
                    after_char = codepoint;
                }
            }
        }

        const left_flanking = num_delims > 0 and !unicode.isWhitespace(after_char) and !(unicode.isPunctuation(after_char) and !unicode.isWhitespace(before_char) and !unicode.isPunctuation(before_char));
        const right_flanking = num_delims > 0 and !unicode.isWhitespace(before_char) and !(unicode.isPunctuation(before_char) and !unicode.isWhitespace(after_char) and !unicode.isPunctuation(after_char));

        if (c == '_') {
            return ScanResult{
                .num_delims = num_delims,
                .can_open = left_flanking and (!right_flanking or unicode.isPunctuation(before_char)),
                .can_close = right_flanking and (!left_flanking or unicode.isPunctuation(after_char)),
            };
        } else if (c == '\'' or c == '"') {
            return ScanResult{
                .num_delims = num_delims,
                .can_open = left_flanking and !right_flanking and before_char != ']' and before_char != ')',
                .can_close = right_flanking,
            };
        } else {
            return ScanResult{
                .num_delims = num_delims,
                .can_open = left_flanking,
                .can_close = right_flanking,
            };
        }
    }

    fn pushDelimiter(self: *Subject, c: u8, can_open: bool, can_close: bool, inl: *nodes.AstNode) !void {
        var delimiter = try self.allocator.create(Delimiter);
        delimiter.* = .{
            .inl = inl,
            .length = inl.data.value.text().?.len,
            .delim_char = c,
            .can_open = can_open,
            .can_close = can_close,
            .prev = self.last_delimiter,
            .next = null,
        };
        if (delimiter.prev) |prev| {
            prev.next = delimiter;
        }
        self.last_delimiter = delimiter;
    }

    fn insertEmph(self: *Subject, opener: *Delimiter, closer: *Delimiter) !?*Delimiter {
        const opener_char = opener.inl.data.value.text().?[0];
        var opener_num_chars = opener.inl.data.value.text().?.len;
        var closer_num_chars = closer.inl.data.value.text().?.len;
        const use_delims: u8 = if (closer_num_chars >= 2 and opener_num_chars >= 2) 2 else 1;

        opener_num_chars -= use_delims;
        closer_num_chars -= use_delims;

        opener.inl.data.value.text_mut().?.items.len = opener_num_chars;
        closer.inl.data.value.text_mut().?.items.len = closer_num_chars;

        var delim = closer.prev;
        while (delim != null and delim != opener) {
            self.removeDelimiter(delim.?);
            delim = delim.?.prev;
        }

        var emph = try self.makeInline(if (use_delims == 1) .Emph else .Strong);
        var tmp = opener.inl.next.?;
        while (tmp != closer.inl) {
            var next = tmp.next;
            emph.append(tmp);
            if (next) |n| {
                tmp = n;
            } else {
                break;
            }
        }
        opener.inl.insertAfter(emph);

        if (opener_num_chars == 0) {
            opener.inl.detachDeinit();
            self.removeDelimiter(opener);
        }

        if (closer_num_chars == 0) {
            closer.inl.detachDeinit();
            self.removeDelimiter(closer);
            return closer.next;
        } else {
            return closer;
        }
    }

    fn handleCloseBracket(self: *Subject) *nodes.AstNode {
        unreachable;
    }
};

const Delimiter = struct {
    inl: *nodes.AstNode,
    length: usize,
    delim_char: u8,
    can_open: bool,
    can_close: bool,
    prev: ?*Delimiter,
    next: ?*Delimiter,
};

const Bracket = struct {
    previous_delimiter: ?*Delimiter,
    inl_text: *nodes.AstNode,
    position: usize,
    image: bool,
    active: bool,
    bracket_after: bool,
};
