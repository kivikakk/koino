const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const assert = std.debug.assert;
const zunicode = @import("zunicode");

const nodes = @import("nodes.zig");
const strings = @import("strings.zig");
const Options = @import("options.zig").Options;
const scanners = @import("scanners.zig");
const Reference = @import("parser.zig").Reference;

const MAX_BACKTICKS = 80;
const MAX_LINK_LABEL_LENGTH = 1000;

pub const ParseError = error{ OutOfMemory, InvalidUtf8 };

pub const Subject = struct {
    allocator: *mem.Allocator,
    refmap: *std.StringHashMap(Reference),
    options: *const Options,
    input: []const u8,
    pos: usize = 0,
    last_delimiter: ?*Delimiter = null,
    brackets: std.ArrayList(Bracket),
    backticks: [MAX_BACKTICKS + 1]usize = [_]usize{0} ** (MAX_BACKTICKS + 1),
    scanned_for_backticks: bool = false,
    special_chars: *const [256]bool,
    skip_chars: *const [256]bool,

    pub fn init(allocator: *mem.Allocator, refmap: *std.StringHashMap(Reference), options: *const Options, special_chars: *const [256]bool, skip_chars: *const [256]bool, input: []const u8) Subject {
        var s = Subject{
            .allocator = allocator,
            .refmap = refmap,
            .options = options,
            .input = input,
            .brackets = std.ArrayList(Bracket).init(allocator),
            .special_chars = special_chars,
            .skip_chars = skip_chars,
        };
        return s;
    }

    pub fn setCharsForOptions(options: *const Options, special_chars: *[256]bool, skip_chars: *[256]bool) void {
        for ([_]u8{ '\n', '\r', '_', '*', '"', '`', '\'', '\\', '&', '<', '[', ']', '!' }) |c| {
            special_chars.*[c] = true;
        }
        if (options.extensions.strikethrough) {
            special_chars.*['~'] = true;
            skip_chars.*['~'] = true;
        }
        if (options.parse.smart) {
            for ([_]u8{ '"', '\'', '.', '-' }) |c| {
                special_chars.*[c] = true;
            }
        }
    }

    pub fn deinit(self: *Subject) void {
        self.brackets.deinit();
    }

    pub fn parseInline(self: *Subject, node: *nodes.AstNode) ParseError!bool {
        const c = self.peekChar() orelse return false;
        var new_inl: ?*nodes.AstNode = null;

        switch (c) {
            0 => return false,
            '\n', '\r' => new_inl = try self.handleNewLine(),
            '`' => new_inl = try self.handleBackticks(),
            '\\' => new_inl = try self.handleBackslash(),
            '&' => new_inl = try self.handleEntity(),
            '<' => new_inl = try self.handlePointyBrace(),
            '*', '_', '\'', '"' => new_inl = try self.handleDelim(c),
            '-' => new_inl = try self.handleHyphen(),
            '.' => new_inl = try self.handlePeriod(),
            '[' => {
                self.pos += 1;
                var inl = try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "[") });
                try self.pushBracket(.Link, inl);
                new_inl = inl;
            },
            ']' => new_inl = try self.handleCloseBracket(),
            '!' => {
                self.pos += 1;
                if (self.peekChar() orelse 0 == '[') {
                    self.pos += 1;
                    var inl = try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "![") });
                    try self.pushBracket(.Image, inl);
                    new_inl = inl;
                } else {
                    new_inl = try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "!") });
                }
            },
            else => {
                if (self.options.extensions.strikethrough and c == '~') {
                    new_inl = try self.handleDelim(c);
                } else {
                    const endpos = self.findSpecialChar();
                    var contents = self.input[self.pos..endpos];
                    self.pos = endpos;

                    if (self.peekChar()) |n| {
                        if (strings.isLineEndChar(n)) {
                            contents = strings.rtrim(contents);
                        }
                    }

                    new_inl = try self.makeInline(.{ .Text = try self.allocator.dupe(u8, contents) });
                }
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

    fn makeAutolink(self: *Subject, url: []const u8, kind: nodes.AutolinkType) !*nodes.AstNode {
        var inl = try self.makeInline(.{
            .Link = .{
                .url = try strings.cleanAutolink(self.allocator, url, kind),
                .title = "",
            },
        });
        inl.append(try self.makeInline(.{ .Text = try strings.unescapeHtml(self.allocator, url) }));
        return inl;
    }

    pub fn processEmphasis(self: *Subject, stack_bottom: ?*Delimiter) !void {
        var closer = self.last_delimiter;

        var openers_bottom: [3][128]?*Delimiter = [_][128]?*Delimiter{[_]?*Delimiter{null} ** 128} ** 3;
        for (openers_bottom) |*i| {
            i['*'] = stack_bottom;
            i['_'] = stack_bottom;
            i['\''] = stack_bottom;
            i['"'] = stack_bottom;
            if (self.options.extensions.strikethrough)
                i['~'] = stack_bottom;
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

                if (closer.?.delim_char == '*' or closer.?.delim_char == '_' or
                    (self.options.extensions.strikethrough and closer.?.delim_char == '~'))
                {
                    if (opener_found) {
                        closer = try self.insertEmph(opener.?, closer.?);
                    } else {
                        closer = closer.?.next;
                    }
                } else if (closer.?.delim_char == '\'') {
                    var al = closer.?.inl.data.value.text_mut().?;
                    self.allocator.free(al.*);
                    al.* = try self.allocator.dupe(u8, "’");
                    if (opener_found) {
                        al = opener.?.inl.data.value.text_mut().?;
                        self.allocator.free(al.*);
                        al.* = try self.allocator.dupe(u8, "‘");
                    }
                    closer = closer.?.next;
                } else if (closer.?.delim_char == '"') {
                    var al = closer.?.inl.data.value.text_mut().?;
                    self.allocator.free(al.*);
                    al.* = try self.allocator.dupe(u8, "”");
                    if (opener_found) {
                        al = opener.?.inl.data.value.text_mut().?;
                        self.allocator.free(al.*);
                        al.* = try self.allocator.dupe(u8, "“");
                    }
                    closer = closer.?.next;
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
        self.allocator.destroy(delimiter);
    }

    pub fn popBracket(self: *Subject) bool {
        return self.brackets.popOrNull() != null;
    }

    fn eof(self: *Subject) bool {
        return self.pos >= self.input.len;
    }

    pub fn peekChar(self: *Subject) ?u8 {
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

    pub fn spnl(self: *Subject) void {
        self.skipSpaces();
        if (self.skipLineEnd())
            self.skipSpaces();
    }

    fn findSpecialChar(self: *Subject) usize {
        var n = self.pos;
        while (n < self.input.len) : (n += 1) {
            if (self.special_chars[self.input[n]])
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
            var contents = try self.allocator.alloc(u8, openticks);
            std.mem.set(u8, contents, '`');
            return try self.makeInline(.{ .Text = contents });
        }
    }

    pub fn skipSpaces(self: *Subject) void {
        while (self.peekChar()) |c| {
            if (!(c == ' ' or c == '\t'))
                break;
            self.pos += 1;
        }
    }

    fn handleBackslash(self: *Subject) !*nodes.AstNode {
        self.pos += 1;
        if (ascii.isPunct(self.peekChar() orelse 0)) {
            self.pos += 1;
            var contents = try self.allocator.dupe(u8, self.input[self.pos - 1 .. self.pos]);
            return try self.makeInline(.{ .Text = contents });
        } else if (!self.eof() and self.skipLineEnd()) {
            return try self.makeInline(.LineBreak);
        } else {
            return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "\\") });
        }
    }

    pub fn skipLineEnd(self: *Subject) bool {
        const old_pos = self.pos;
        if (self.peekChar() orelse 0 == '\r') self.pos += 1;
        if (self.peekChar() orelse 0 == '\n') self.pos += 1;
        return self.pos > old_pos or self.eof();
    }

    fn handleEntity(self: *Subject) !*nodes.AstNode {
        self.pos += 1;

        var out = std.ArrayList(u8).init(self.allocator);
        if (try strings.unescapeInto(self.input[self.pos..], &out)) |len| {
            self.pos += len;
            return try self.makeInline(.{ .Text = out.toOwnedSlice() });
        }

        try out.append('&');
        return try self.makeInline(.{ .Text = out.toOwnedSlice() });
    }

    fn handlePointyBrace(self: *Subject) !*nodes.AstNode {
        self.pos += 1;

        if (try scanners.autolinkUri(self.input[self.pos..])) |match_len| {
            var inl = try self.makeAutolink(self.input[self.pos .. self.pos + match_len - 1], .URI);
            self.pos += match_len;
            return inl;
        }

        if (try scanners.autolinkEmail(self.input[self.pos..])) |match_len| {
            var inl = try self.makeAutolink(self.input[self.pos .. self.pos + match_len - 1], .Email);
            self.pos += match_len;
            return inl;
        }

        if (try scanners.htmlTag(self.input[self.pos..])) |match_len| {
            var contents = self.input[self.pos - 1 .. self.pos + match_len];
            var inl = try self.makeInline(.{ .HtmlInline = try self.allocator.dupe(u8, contents) });
            self.pos += match_len;
            return inl;
        }

        return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "<") });
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

        const inl = try self.makeInline(.{ .Text = try self.allocator.dupe(u8, contents) });

        if ((scan.can_open or scan.can_close) and (!(c == '\'' or c == '"') or self.options.parse.smart)) {
            try self.pushDelimiter(c, scan.can_open, scan.can_close, inl);
        }

        return inl;
    }

    fn handleHyphen(self: *Subject) !*nodes.AstNode {
        self.pos += 1;
        var num_hyphens: usize = 1;

        if (!self.options.parse.smart or (self.peekChar() orelse 0) != '-') {
            return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "-") });
        }

        while (self.options.parse.smart and (self.peekChar() orelse 0) == '-') {
            self.pos += 1;
            num_hyphens += 1;
        }

        var ens_ems = if (num_hyphens % 3 == 0)
            [2]usize{ 0, num_hyphens / 3 }
        else if (num_hyphens % 2 == 0)
            [2]usize{ num_hyphens / 2, 0 }
        else if (num_hyphens % 3 == 2)
            [2]usize{ 1, (num_hyphens - 2) / 3 }
        else
            [2]usize{ 2, (num_hyphens - 4) / 3 };

        var text = std.ArrayList(u8).init(self.allocator);

        while (ens_ems[1] > 0) : (ens_ems[1] -= 1)
            try text.appendSlice("—");
        while (ens_ems[0] > 0) : (ens_ems[0] -= 1)
            try text.appendSlice("–");

        return try self.makeInline(.{ .Text = text.toOwnedSlice() });
    }

    fn handlePeriod(self: *Subject) !*nodes.AstNode {
        self.pos += 1;
        if (self.options.parse.smart and (self.peekChar() orelse 0) == @as(u8, '.')) {
            self.pos += 1;
            if (self.peekChar() == @as(u8, '.')) {
                self.pos += 1;
                return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "…") });
            }
            return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "..") });
        }
        return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, ".") });
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
            var utf8 = std.unicode.Utf8View.initUnchecked(self.input[before_char_pos..self.pos]).iterator();
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
            var utf8 = std.unicode.Utf8View.initUnchecked(self.input[after_char_pos..]).iterator();
            if (utf8.nextCodepoint()) |codepoint| {
                if (codepoint >= 256 or !self.skip_chars[codepoint]) {
                    after_char = codepoint;
                }
            }
        }

        const left_flanking = num_delims > 0 and !zunicode.isSpace(after_char) and !(zunicode.isPunct(after_char) and !zunicode.isSpace(before_char) and !zunicode.isPunct(before_char));
        const right_flanking = num_delims > 0 and !zunicode.isSpace(before_char) and !(zunicode.isPunct(before_char) and !zunicode.isSpace(after_char) and !zunicode.isPunct(after_char));

        if (c == '_') {
            return ScanResult{
                .num_delims = num_delims,
                .can_open = left_flanking and (!right_flanking or zunicode.isPunct(before_char)),
                .can_close = right_flanking and (!left_flanking or zunicode.isPunct(after_char)),
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

        if (self.options.extensions.strikethrough and opener_char == '~' and (opener_num_chars != closer_num_chars or opener_num_chars > 0))
            return null;

        var opener_text = opener.inl.data.value.text_mut().?;
        opener_text.* = self.allocator.shrink(opener_text.*, opener_num_chars);
        var closer_text = closer.inl.data.value.text_mut().?;
        closer_text.* = self.allocator.shrink(closer_text.*, closer_num_chars);

        var delim = closer.prev;
        while (delim != null and delim != opener) {
            var prev = delim.?.prev;
            self.removeDelimiter(delim.?);
            delim = prev;
        }

        var value: nodes.NodeValue = undefined;
        if (self.options.extensions.strikethrough and opener_char == '~') {
            value = .Strikethrough;
        } else if (use_delims == 1) {
            value = .Emph;
        } else {
            value = .Strong;
        }
        var emph = try self.makeInline(value);
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
            var next = closer.next;
            self.removeDelimiter(closer);
            return next;
        } else {
            return closer;
        }
    }

    fn pushBracket(self: *Subject, kind: BracketKind, inl_text: *nodes.AstNode) !void {
        const len = self.brackets.items.len;
        if (len > 0)
            self.brackets.items[len - 1].bracket_after = true;
        try self.brackets.append(.{
            .previous_delimiter = self.last_delimiter,
            .inl_text = inl_text,
            .position = self.pos,
            .kind = kind,
            .active = true,
            .bracket_after = false,
        });
    }

    fn handleCloseBracket(self: *Subject) !?*nodes.AstNode {
        self.pos += 1;
        const initial_pos = self.pos;

        const brackets_len = self.brackets.items.len;
        if (brackets_len == 0) {
            return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "]") });
        }

        if (!self.brackets.items[brackets_len - 1].active) {
            _ = self.brackets.pop();
            return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "]") });
        }

        const kind = self.brackets.items[brackets_len - 1].kind;
        const after_link_text_pos = self.pos;

        var sps: usize = 0;
        var url: []const u8 = "";
        var n: usize = 0;
        if (self.peekChar() orelse 0 == '(' and blk: {
            sps = (try scanners.spacechars(self.input[self.pos + 1 ..])) orelse 0;
            break :blk manualScanLinkUrl(self.input[self.pos + 1 + sps ..], &url, &n);
        }) {
            const starturl = self.pos + 1 + sps;
            const endurl = starturl + n;
            const starttitle = endurl + ((try scanners.spacechars(self.input[endurl..])) orelse 0);
            const endtitle = if (starttitle == endurl) starttitle else starttitle + ((try scanners.linkTitle(self.input[starttitle..])) orelse 0);
            const endall = endtitle + ((try scanners.spacechars(self.input[endtitle..])) orelse 0);

            if (endall < self.input.len and self.input[endall] == ')') {
                self.pos = endall + 1;
                var cleanUrl = try strings.cleanUrl(self.allocator, url);
                var cleanTitle = try strings.cleanTitle(self.allocator, self.input[starttitle..endtitle]);
                try self.closeBracketMatch(kind, cleanUrl, cleanTitle);
                return null;
            } else {
                self.pos = after_link_text_pos;
            }
        }

        var label: ?[]const u8 = null;
        if (self.linkLabel()) |lab| {
            label = lab;
        }

        if (label == null) {
            self.pos = initial_pos;
        }

        if ((label == null or label.?.len == 0) and !self.brackets.items[brackets_len - 1].bracket_after) {
            label = self.input[self.brackets.items[brackets_len - 1].position .. initial_pos - 1];
        }

        var normalized = try strings.normalizeLabel(self.allocator, label orelse "");
        defer self.allocator.free(normalized);
        var maybe_ref = if (label != null) self.refmap.get(normalized) else null;

        if (maybe_ref) |ref| {
            try self.closeBracketMatch(kind, try self.allocator.dupe(u8, ref.url), try self.allocator.dupe(u8, ref.title));
            return null;
        }

        _ = self.brackets.pop();
        self.pos = initial_pos;
        return try self.makeInline(.{ .Text = try self.allocator.dupe(u8, "]") });
    }

    pub fn linkLabel(self: *Subject) ?[]const u8 {
        const startpos = self.pos;
        if (self.peekChar() orelse 0 != '[') {
            return null;
        }

        self.pos += 1;

        var length: usize = 0;
        var c: u8 = 0;
        while (true) {
            c = self.peekChar() orelse 0;
            if (c == '[' or c == ']') {
                break;
            }

            if (c == '\\') {
                self.pos += 1;
                length += 1;
                if (ascii.isPunct(self.peekChar() orelse 0)) {
                    self.pos += 1;
                    length += 1;
                }
            } else {
                self.pos += 1;
                length += 1;
            }
            if (length > MAX_LINK_LABEL_LENGTH) {
                self.pos = startpos;
                return null;
            }
        }
        if (c == ']') {
            const raw_label = strings.trim(self.input[startpos + 1 .. self.pos]);
            self.pos += 1;
            return raw_label;
        } else {
            self.pos = startpos;
            return null;
        }
    }

    /// Takes ownership of `url' and `title'.
    fn closeBracketMatch(self: *Subject, kind: BracketKind, url: []u8, title: []u8) !void {
        const nl = nodes.NodeLink{ .url = url, .title = title };
        var inl = try self.makeInline(switch (kind) {
            .Link => .{ .Link = nl },
            .Image => .{ .Image = nl },
        });

        var brackets_len = self.brackets.items.len;
        self.brackets.items[brackets_len - 1].inl_text.insertBefore(inl);
        var tmpch = self.brackets.items[brackets_len - 1].inl_text.next;
        while (tmpch) |tmp| {
            tmpch = tmp.next;
            inl.append(tmp);
        }
        self.brackets.items[brackets_len - 1].inl_text.detachDeinit(); // XXX ???
        const previous_delimiter = self.brackets.items[brackets_len - 1].previous_delimiter;
        try self.processEmphasis(previous_delimiter);
        _ = self.brackets.pop();
        brackets_len -= 1;

        if (kind == .Link) {
            var i = @intCast(i32, brackets_len) - 1;
            while (i >= 0) : (i -= 1) {
                if (self.brackets.items[@intCast(usize, i)].kind == .Link) {
                    if (!self.brackets.items[@intCast(usize, i)].active) {
                        break;
                    } else {
                        self.brackets.items[@intCast(usize, i)].active = false;
                    }
                }
            }
        }
    }

    pub fn manualScanLinkUrl(input: []const u8, url: *[]const u8, n: *usize) bool {
        const len = input.len;
        var i: usize = 0;

        if (i < len and input[i] == '<') {
            i += 1;
            while (i < len) {
                switch (input[i]) {
                    '>' => {
                        i += 1;
                        break;
                    },
                    '\\' => {
                        i += 2;
                    },
                    '\n', '<' => {
                        return false;
                    },
                    else => {
                        i += 1;
                    },
                }
            }
        } else {
            return manualScanLinkUrl2(input, url, n);
        }

        if (i >= len) {
            return false;
        } else {
            url.* = input[1 .. i - 1];
            n.* = i;
            return true;
        }
    }

    fn manualScanLinkUrl2(input: []const u8, url: *[]const u8, n: *usize) bool {
        const len = input.len;
        var i: usize = 0;
        var nb_p: usize = 0;

        while (i < len) {
            if (input[i] == '\\' and i + 1 < len and ascii.isPunct(input[i + 1])) {
                i += 2;
            } else if (input[i] == '(') {
                nb_p += 1;
                i += 1;
                if (nb_p > 32)
                    return false;
            } else if (input[i] == ')') {
                if (nb_p == 0)
                    break;
                nb_p -= 1;
                i += 1;
            } else if (ascii.isSpace(input[i])) {
                if (i == 0)
                    return false;
                break;
            } else {
                i += 1;
            }
        }

        if (i >= len) {
            return false;
        } else {
            url.* = input[0..i];
            n.* = i;
            return true;
        }
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
    kind: BracketKind,
    active: bool,
    bracket_after: bool,
};

const BracketKind = enum { Link, Image };
