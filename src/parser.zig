const std = @import("std");
const assert = std.debug.assert;

const main = @import("main.zig");
const strings = @import("strings.zig");
const nodes = @import("nodes.zig");
const scanners = @import("scanners.zig");
const inlines = @import("inlines.zig");

const TAB_STOP = 4;
const CODE_INDENT = 4;

pub const Parser = struct {
    allocator: *std.mem.Allocator,
    root: *nodes.AstNode,
    current: *nodes.AstNode,

    line_number: u32 = 0,
    offset: usize = 0,
    column: usize = 0,
    first_nonspace: usize = 0,
    first_nonspace_column: usize = 0,
    indent: usize = 0,
    blank: bool = false,
    partially_consumed_tab: bool = false,
    last_line_length: usize = 0,

    pub fn feed(self: *Parser, s: []const u8) !void {
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

    pub fn finish(self: *Parser) !*nodes.AstNode {
        try self.finalizeDocument();
        return self.root;
    }

    fn findFirstNonspace(self: *Parser, line: []const u8) void {
        self.first_nonspace = self.offset;
        self.first_nonspace_column = self.column;

        var chars_to_tab = TAB_STOP - (self.column % TAB_STOP);

        while (true) {
            if (self.first_nonspace >= line.len) {
                break;
            }
            switch (line[self.first_nonspace]) {
                ' ' => {
                    self.first_nonspace += 1;
                    self.first_nonspace_column += 1;
                    chars_to_tab -= 1;
                    if (chars_to_tab == 0) {
                        chars_to_tab = TAB_STOP;
                    }
                },
                9 => {
                    self.first_nonspace += 1;
                    self.first_nonspace_column += chars_to_tab;
                    chars_to_tab = TAB_STOP;
                },
                else => break,
            }
        }

        self.indent = self.first_nonspace_column - self.column;
        self.blank = self.first_nonspace < line.len and strings.isLineEndChar(line[self.first_nonspace]);
    }

    fn processLine(self: *Parser, input: []const u8) !void {
        var line: []const u8 = undefined;
        if (input.len == 0 or !strings.isLineEndChar(input[input.len - 1])) {
            unreachable;
        } else {
            line = input;
        }

        self.offset = 0;
        self.column = 0;
        self.blank = false;
        self.partially_consumed_tab = false;

        if (self.line_number == 0 and line.len >= 3 and std.mem.eql(u8, line[0..3], "\u{feff}")) {
            self.offset += 3;
        }

        self.line_number += 1;

        var all_matched = true;
        const result = self.checkOpenBlocks(line);
        if (result.container) |last_matched_container| {
            const current = self.current;
            const container = try self.openNewBlocks(last_matched_container, line, result.all_matched);
            if (current == self.current) {
                try self.addTextToContainer(container, last_matched_container, line);
            }
        }

        self.last_line_length = line.len;
        if (self.last_line_length > 0 and line[self.last_line_length - 1] == '\n') {
            self.last_line_length -= 1;
        }
        if (self.last_line_length > 0 and line[self.last_line_length - 1] == '\r') {
            self.last_line_length -= 1;
        }
    }

    const CheckOpenBlocksResult = struct {
        all_matched: bool = false,
        container: ?*nodes.AstNode,
    };

    fn checkOpenBlocks(self: *Parser, line: []const u8) CheckOpenBlocksResult {
        const result = self.checkOpenBlocksInner(self.root, line);
        if (result.container) |container| {
            return .{
                .all_matched = result.all_matched,
                .container = if (result.all_matched) container else container.parent.?,
            };
        }
        return result;
    }

    fn checkOpenBlocksInner(self: *Parser, start_container: *nodes.AstNode, line: []const u8) CheckOpenBlocksResult {
        var container = start_container;

        while (container.lastChildIsOpen()) {
            container = container.last_child.?;
            self.findFirstNonspace(line);

            switch (container.data.value) {
                .BlockQuote => {
                    if (!self.parseBlockQuotePrefix(line)) {
                        return .{ .container = container };
                    }
                },
                .Item => unreachable,
                .CodeBlock => {
                    switch (self.parseCodeBlockPrefix(line, container)) {
                        .DoNotContinue => {
                            return .{ .container = null };
                        },
                        .NoMatch => {
                            return .{ .container = container };
                        },
                        .Match => {},
                    }
                },
                .HtmlBlock => |nhb| {
                    if (!self.parseHtmlBlockPrefix(nhb.block_type)) {
                        return .{ .container = container };
                    }
                },
                .Paragraph => {
                    if (self.blank) {
                        return .{ .container = container };
                    }
                },
                .Heading => {
                    return .{ .container = container };
                },
                else => {},
            }
        }

        return .{
            .all_matched = true,
            .container = container,
        };
    }

    fn openNewBlocks(self: *Parser, input_container: *nodes.AstNode, line: []const u8, all_matched: bool) !*nodes.AstNode {
        var container = input_container;
        var maybe_lazy = switch (self.current.data.value) {
            .Paragraph => true,
            else => false,
        };

        while (switch (container.data.value) {
            .CodeBlock, .HtmlBlock => false,
            else => true,
        }) {
            self.findFirstNonspace(line);
            const indented = self.indent >= CODE_INDENT;

            if (!indented and line[self.first_nonspace] == '>') {
                const offset = self.first_nonspace + 1 - self.offset;
                self.advanceOffset(line, offset, false);
                if (strings.isSpaceOrTab(line[self.offset])) {
                    self.advanceOffset(line, 1, true);
                }
                container = try self.addChild(container, .BlockQuote);
            }
            // ...
            else {
                // TODO: table stuff
                break;
            }

            if (container.data.value.acceptsLines()) {
                break;
            }

            maybe_lazy = false;
        }

        return container;
    }

    fn addChild(self: *Parser, input_parent: *nodes.AstNode, value: nodes.NodeValue) !*nodes.AstNode {
        var parent = input_parent;
        while (!parent.data.value.canContainType(value)) {
            parent = self.finalize(parent).?;
        }

        var node = try nodes.AstNode.create(self.allocator, .{
            .value = value,
            .start_line = self.line_number,
            .content = std.ArrayList(u8).init(self.allocator),
        });
        parent.append(node);
        return node;
    }

    fn addTextToContainer(self: *Parser, input_container: *nodes.AstNode, last_matched_container: *nodes.AstNode, line: []const u8) !void {
        var container = input_container;
        self.findFirstNonspace(line);

        if (self.blank) {
            if (container.last_child) |last_child| {
                last_child.data.last_line_blank = true;
            }
        }

        container.data.last_line_blank = self.blank and
            switch (container.data.value) {
            .BlockQuote, .Heading, .ThematicBreak => false,
            .CodeBlock => |ncb| !ncb.fenced,
            .Item => container.first_child != null or container.data.start_line != self.line_number,
            else => true,
        };

        var tmp = container;
        while (tmp.parent) |parent| {
            parent.data.last_line_blank = false;
            tmp = parent;
        }

        if (self.current != last_matched_container and container == last_matched_container and !self.blank and self.current.data.value == .Paragraph) {
            try self.addLine(self.current, line);
            return;
        }

        while (self.current != last_matched_container) {
            self.current = self.finalize(self.current).?;
        }

        switch (container.data.value) {
            .CodeBlock => {
                try self.addLine(container, line);
            },
            .HtmlBlock => |nhb| {
                try self.addLine(container, line);
                const matches_end_condition = switch (nhb.block_type) {
                    1 => scanners.htmlBlockEnd1(line[self.first_nonspace..]),
                    2 => scanners.htmlBlockEnd2(line[self.first_nonspace..]),
                    3 => scanners.htmlBlockEnd3(line[self.first_nonspace..]),
                    4 => scanners.htmlBlockEnd4(line[self.first_nonspace..]),
                    5 => scanners.htmlBlockEnd5(line[self.first_nonspace..]),
                    else => false,
                };

                if (matches_end_condition) {
                    container = self.finalize(container).?;
                }
            },
            else => {
                if (self.blank) {
                    // do nothing
                } else if (container.data.value.acceptsLines()) {
                    var consider_line: []const u8 = line;

                    switch (container.data.value) {
                        .Heading => |nh| if (!nh.setext) {
                            consider_line = strings.chopTrailingHashtags(line);
                        },
                        else => {},
                    }

                    const count = self.first_nonspace - self.offset;
                    if (self.first_nonspace <= consider_line.len) {
                        self.advanceOffset(consider_line, count, false);
                        try self.addLine(container, consider_line);
                    }
                } else {
                    container = try self.addChild(container, .Paragraph);
                    const count = self.first_nonspace - self.offset;
                    self.advanceOffset(line, count, false);
                    try self.addLine(container, line);
                }
            },
        }

        self.current = container;
    }

    fn addLine(self: *Parser, node: *nodes.AstNode, line: []const u8) !void {
        assert(node.data.open);
        if (self.partially_consumed_tab) {
            self.offset += 1;
            var chars_to_tab = TAB_STOP - (self.column % TAB_STOP);
            while (chars_to_tab > 0) : (chars_to_tab -= 1) {
                try node.data.content.append(' ');
            }
        }
        if (self.offset < line.len) {
            try node.data.content.appendSlice(line[self.offset..]);
        }
    }

    fn finalizeDocument(self: *Parser) !void {
        while (self.current != self.root) {
            self.current = self.finalize(self.current).?;
        }

        _ = self.finalize(self.root);
        try self.processInlines();
    }

    fn finalize(self: *Parser, node: *nodes.AstNode) ?*nodes.AstNode {
        assert(node.data.open);
        node.data.open = false;
        const parent = node.parent;

        switch (node.data.value) {
            .Paragraph => {
                if (strings.isBlank(node.data.content.span())) {
                    node.detachDeinit();
                }
            },
            .CodeBlock => {
                unreachable;
            },
            .HtmlBlock => |nhb| {
                unreachable;
            },
            .List => {
                unreachable;
            },
            else => {},
        }

        return parent;
    }

    fn processInlines(self: *Parser) !void {
        try self.processInlinesNode(self.root);
    }

    const InlineParseError = error{ OutOfMemory, InvalidUtf8 };

    fn processInlinesNode(self: *Parser, node: *nodes.AstNode) InlineParseError!void {
        if (node.data.value.containsInlines()) {
            try self.parseInlines(node);
        }
        var child = node.first_child;
        while (child) |ch| {
            try self.processInlinesNode(ch);
            child = ch.next;
        }

        // TODO:
        // var it = node.descendantsIterator();
        // while (it.next()) |descendant| {
        //     if (descendant.data.value.containsInlines()) {
        //         try self.parseInlines(descendant);
        //     }
        // }
    }

    fn parseInlines(self: *Parser, node: *nodes.AstNode) !void {
        var content = strings.rtrim(node.data.content.span());
        var subj = inlines.Subject.init(self.allocator, content);
        while (try subj.parseInline(node)) {}
        try subj.processEmphasis(null);
        while (subj.popBracket()) {}
    }

    fn advanceOffset(self: *Parser, line: []const u8, in_count: usize, columns: bool) void {
        var count = in_count;
        while (count > 0) {
            switch (line[self.offset]) {
                '\t' => {
                    const chars_to_tab = TAB_STOP - (self.column % TAB_STOP);
                    if (columns) {
                        self.partially_consumed_tab = chars_to_tab > count;
                        const chars_to_advance = std.math.min(count, chars_to_tab);
                        self.column += chars_to_advance;
                        self.offset += @as(u8, if (self.partially_consumed_tab) 0 else 1);
                        count -= chars_to_advance;
                    } else {
                        self.partially_consumed_tab = false;
                        self.column += chars_to_tab;
                        self.offset += 1;
                        count -= 1;
                    }
                },
                else => {
                    self.partially_consumed_tab = false;
                    self.offset += 1;
                    self.column += 1;
                    count -= 1;
                },
            }
        }
    }

    fn parseBlockQuotePrefix(self: *Parser, line: []const u8) bool {
        var indent = self.indent;
        if (indent <= 3 and line[self.first_nonspace] == '>') {
            self.advanceOffset(line, indent + 1, true);

            if (strings.isSpaceOrTab(line[self.offset])) {
                self.advanceOffset(line, 1, true);
            }

            return true;
        }

        return false;
    }

    const CodeBlockPrefixParseResult = enum {
        DoNotContinue,
        NoMatch,
        Match,
    };

    fn parseCodeBlockPrefix(self: *Parser, line: []const u8, container: *nodes.AstNode) CodeBlockPrefixParseResult {
        unreachable;
    }

    fn parseHtmlBlockPrefix(self: *Parser, t: u8) bool {
        return switch (t) {
            1, 2, 3, 4, 5 => true,
            6, 7 => !self.blank,
            else => unreachable,
        };
    }
};

test "accepts multiple lines" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var output = try main.markdownToHtml(&gpa.allocator, "hello\nthere\n");
    defer gpa.allocator.free(output);

    std.testing.expectEqualStrings("<p>hello\nthere</p>\n", output);
}
