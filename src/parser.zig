const std = @import("std");
const assert = std.debug.assert;
const ascii = std.ascii;

const main = @import("main.zig");
const strings = @import("strings.zig");
const nodes = @import("nodes.zig");
const scanners = @import("scanners.zig");
const inlines = @import("inlines.zig");
const Options = @import("options.zig").Options;
const table = @import("table.zig");
const AutolinkProcessor = @import("autolink.zig").AutolinkProcessor;

const TAB_STOP = 4;
const CODE_INDENT = 4;

pub const Reference = struct {
    url: []u8,
    title: []u8,
};

pub const Parser = struct {
    allocator: *std.mem.Allocator,
    refmap: std.StringHashMap(Reference),
    hack_refmapKeys: std.ArrayList([]u8),
    root: *nodes.AstNode,
    current: *nodes.AstNode,
    options: Options,

    line_number: u32 = 0,
    offset: usize = 0,
    column: usize = 0,
    first_nonspace: usize = 0,
    first_nonspace_column: usize = 0,
    indent: usize = 0,
    blank: bool = false,
    partially_consumed_tab: bool = false,
    last_line_length: usize = 0,

    special_chars: [256]bool = [_]bool{false} ** 256,
    skip_chars: [256]bool = [_]bool{false} ** 256,

    pub fn init(allocator: *std.mem.Allocator, options: Options) !Parser {
        var root = try nodes.AstNode.create(allocator, .{
            .value = .Document,
            .content = std.ArrayList(u8).init(allocator),
        });

        var parser = Parser{
            .allocator = allocator,
            .refmap = std.StringHashMap(Reference).init(allocator),
            .hack_refmapKeys = std.ArrayList([]u8).init(allocator),
            .root = root,
            .current = root,
            .options = options,
        };

        inlines.Subject.setCharsForOptions(&options, &parser.special_chars, &parser.skip_chars);

        return parser;
    }

    pub fn deinit(self: *Parser) void {
        var it = self.refmap.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.url);
            self.allocator.free(entry.value_ptr.title);
        }
        self.refmap.deinit();
    }

    pub fn feed(self: *Parser, s: []const u8) !void {
        var i: usize = 0;
        var sz = s.len;
        var linebuf = std.ArrayList(u8).init(self.allocator);
        defer linebuf.deinit();

        while (i < sz) {
            var process = true;
            var eol = i;
            while (eol < sz) {
                if (strings.isLineEndChar(s[eol]))
                    break;
                if (s[eol] == 0) {
                    process = false;
                    break;
                }
                eol += 1;
            }

            if (process) {
                if (linebuf.items.len != 0) {
                    try linebuf.appendSlice(s[i..eol]);
                    try self.processLine(linebuf.items);
                    linebuf.items.len = 0;
                } else if (sz > eol and s[eol] == '\n') {
                    try self.processLine(s[i .. eol + 1]);
                } else {
                    try self.processLine(s[i..eol]);
                }

                i = eol;
                if (i < sz and s[i] == '\r') i += 1;
                if (i < sz and s[i] == '\n') i += 1;
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
        try self.postprocessTextNodes();
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
        var new_line: ?[]u8 = null;
        if (input.len == 0 or !strings.isLineEndChar(input[input.len - 1])) {
            new_line = try self.allocator.alloc(u8, input.len + 1);
            std.mem.copy(u8, new_line.?, input);
            new_line.?[input.len] = '\n';
            line = new_line.?;
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

        const result = try self.checkOpenBlocks(line);
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

        if (new_line) |nl| self.allocator.free(nl);
    }

    const CheckOpenBlocksResult = struct {
        all_matched: bool = false,
        container: ?*nodes.AstNode,
    };

    fn checkOpenBlocks(self: *Parser, line: []const u8) !CheckOpenBlocksResult {
        const result = try self.checkOpenBlocksInner(self.root, line);
        if (result.container) |container| {
            return CheckOpenBlocksResult{
                .all_matched = result.all_matched,
                .container = if (result.all_matched) container else container.parent.?,
            };
        }
        return result;
    }

    fn checkOpenBlocksInner(self: *Parser, start_container: *nodes.AstNode, line: []const u8) !CheckOpenBlocksResult {
        var container = start_container;

        while (container.lastChildIsOpen()) {
            container = container.last_child.?;
            self.findFirstNonspace(line);

            switch (container.data.value) {
                .BlockQuote => {
                    if (!self.parseBlockQuotePrefix(line)) {
                        return CheckOpenBlocksResult{ .container = container };
                    }
                },
                .Item => |*nl| {
                    if (!self.parseNodeItemPrefix(line, container, nl)) {
                        return CheckOpenBlocksResult{ .container = container };
                    }
                },
                .CodeBlock => {
                    switch (try self.parseCodeBlockPrefix(line, container)) {
                        .DoNotContinue => {
                            return CheckOpenBlocksResult{ .container = null };
                        },
                        .NoMatch => {
                            return CheckOpenBlocksResult{ .container = container };
                        },
                        .Match => {},
                    }
                },
                .HtmlBlock => |nhb| {
                    if (!self.parseHtmlBlockPrefix(nhb.block_type)) {
                        return CheckOpenBlocksResult{ .container = container };
                    }
                },
                .Paragraph => {
                    if (self.blank) {
                        return CheckOpenBlocksResult{ .container = container };
                    }
                },
                .Table => {
                    if (!(try table.matches(self.allocator, line[self.first_nonspace..]))) {
                        return CheckOpenBlocksResult{ .container = container };
                    }
                },
                .Heading, .TableRow, .TableCell => {
                    return CheckOpenBlocksResult{ .container = container };
                },
                .Document, .List, .ThematicBreak, .Text, .SoftBreak, .LineBreak, .Code, .HtmlInline, .Emph, .Strong, .Strikethrough, .Link, .Image => {},
            }
        }

        return CheckOpenBlocksResult{
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

        var matched: usize = undefined;
        var nl: nodes.NodeList = undefined;
        var sc: scanners.SetextChar = undefined;

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
            } else if (!indented and try scanners.unwrap(scanners.atxHeadingStart(line[self.first_nonspace..]), &matched)) {
                const heading_startpos = self.first_nonspace;
                const offset = self.offset;
                self.advanceOffset(line, heading_startpos + matched - offset, false);
                container = try self.addChild(container, .{ .Heading = .{} });

                var hashpos = std.mem.indexOfScalar(u8, line[self.first_nonspace..], '#').? + self.first_nonspace;
                var level: u8 = 0;
                while (line[hashpos] == '#') {
                    if (level < 6)
                        level += 1;
                    hashpos += 1;
                }

                container.data.value = .{ .Heading = .{ .level = level, .setext = false } };
            } else if (!indented and try scanners.unwrap(scanners.openCodeFence(line[self.first_nonspace..]), &matched)) {
                const first_nonspace = self.first_nonspace;
                const offset = self.offset;
                const ncb = nodes.NodeCodeBlock{
                    .fenced = true,
                    .fence_char = line[first_nonspace],
                    .fence_length = matched,
                    .fence_offset = first_nonspace - offset,
                    .info = null,
                    .literal = std.ArrayList(u8).init(self.allocator),
                };
                container = try self.addChild(container, .{ .CodeBlock = ncb });
                self.advanceOffset(line, first_nonspace + matched - offset, false);
            } else if (!indented and ((try scanners.htmlBlockStart(line[self.first_nonspace..], &matched)) or switch (container.data.value) {
                .Paragraph => false,
                else => try scanners.htmlBlockStart7(line[self.first_nonspace..], &matched),
            })) {
                const nhb = nodes.NodeHtmlBlock{
                    .block_type = @truncate(u8, matched),
                    .literal = std.ArrayList(u8).init(self.allocator),
                };
                container = try self.addChild(container, .{ .HtmlBlock = nhb });
            } else if (!indented and switch (container.data.value) {
                .Paragraph => try scanners.setextHeadingLine(line[self.first_nonspace..], &sc),
                else => false,
            }) {
                const has_content = try self.resolveReferenceLinkDefinitions(&container.data.content);
                if (has_content) {
                    container.data.value = .{
                        .Heading = .{
                            .level = switch (sc) {
                                .Equals => 1,
                                .Hyphen => 2,
                            },
                            .setext = true,
                        },
                    };
                    const adv = line.len - 1 - self.offset;
                    self.advanceOffset(line, adv, false);
                }
            } else if (!indented and !(switch (container.data.value) {
                .Paragraph => !all_matched,
                else => false,
            }) and try scanners.unwrap(scanners.thematicBreak(line[self.first_nonspace..]), &matched)) {
                container = try self.addChild(container, .ThematicBreak);
                const adv = line.len - 1 - self.offset;
                self.advanceOffset(line, adv, false);
            } else if ((!indented or switch (container.data.value) {
                .List => true,
                else => false,
            }) and self.indent < 4 and parseListMarker(line, self.first_nonspace, switch (container.data.value) {
                .Paragraph => true,
                else => false,
            }, &matched, &nl)) {
                const offset = self.first_nonspace + matched - self.offset;
                self.advanceOffset(line, offset, false);

                const save_partially_consumed_tab = self.partially_consumed_tab;
                const save_offset = self.offset;
                const save_column = self.column;

                while (self.column - save_column <= 5 and strings.isSpaceOrTab(line[self.offset])) {
                    self.advanceOffset(line, 1, true);
                }

                const i = self.column - save_column;
                if (i >= 5 or i < 1 or strings.isLineEndChar(line[self.offset])) {
                    nl.padding = matched + 1;
                    self.partially_consumed_tab = save_partially_consumed_tab;
                    self.offset = save_offset;
                    self.column = save_column;
                    if (i > 0)
                        self.advanceOffset(line, 1, true);
                } else {
                    nl.padding = matched + i;
                }

                nl.marker_offset = self.indent;

                if (switch (container.data.value) {
                    .List => |*mnl| !listsMatch(&nl, mnl),
                    else => true,
                }) {
                    container = try self.addChild(container, .{ .List = nl });
                }

                container = try self.addChild(container, .{ .Item = nl });
            } else if (indented and !maybe_lazy and !self.blank) {
                self.advanceOffset(line, CODE_INDENT, true);
                container = try self.addChild(container, .{
                    .CodeBlock = .{
                        .fenced = false,
                        .fence_char = 0,
                        .fence_length = 0,
                        .fence_offset = 0,
                        .info = null,
                        .literal = std.ArrayList(u8).init(self.allocator),
                    },
                });
            } else {
                var replace: bool = undefined;
                var new_container = if (!indented and self.options.extensions.table)
                    try table.tryOpeningBlock(self, container, line, &replace)
                else
                    null;

                if (new_container) |new| {
                    if (replace) {
                        container.insertAfter(new);
                        container.detachDeinit();
                        container = new;
                    } else {
                        container = new;
                    }
                } else {
                    break;
                }
            }

            if (container.data.value.acceptsLines()) {
                break;
            }

            maybe_lazy = false;
        }

        return container;
    }

    pub fn addChild(self: *Parser, input_parent: *nodes.AstNode, value: nodes.NodeValue) !*nodes.AstNode {
        var parent = input_parent;
        while (!parent.data.value.canContainType(value)) {
            parent = (try self.finalize(parent)).?;
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
            self.current = (try self.finalize(self.current)).?;
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
                    container = (try self.finalize(container)).?;
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
            self.current = (try self.finalize(self.current)).?;
        }

        _ = try self.finalize(self.root);
        try self.processInlines();
    }

    fn finalize(self: *Parser, node: *nodes.AstNode) !?*nodes.AstNode {
        assert(node.data.open);
        node.data.open = false;
        const parent = node.parent;

        switch (node.data.value) {
            .Paragraph => {
                const has_content = try self.resolveReferenceLinkDefinitions(&node.data.content);
                if (!has_content) {
                    node.detachDeinit();
                }
            },
            .CodeBlock => |*ncb| {
                if (!ncb.fenced) {
                    strings.removeTrailingBlankLines(&node.data.content);
                    try node.data.content.append('\n');
                } else {
                    var pos: usize = 0;
                    while (pos < node.data.content.items.len) : (pos += 1) {
                        if (strings.isLineEndChar(node.data.content.items[pos]))
                            break;
                    }
                    assert(pos < node.data.content.items.len);

                    var info = try strings.cleanUrl(self.allocator, node.data.content.items[0..pos]);
                    if (info.len != 0) {
                        ncb.info = info;
                    }

                    if (node.data.content.items[pos] == '\r') pos += 1;
                    if (node.data.content.items[pos] == '\n') pos += 1;

                    try node.data.content.replaceRange(0, pos, "");
                }
                std.mem.swap(std.ArrayList(u8), &ncb.literal, &node.data.content);
            },
            .HtmlBlock => |*nhb| {
                std.mem.swap(std.ArrayList(u8), &nhb.literal, &node.data.content);
            },
            .List => |*nl| {
                nl.tight = true;
                var it = node.first_child;

                while (it) |item| {
                    if (item.data.last_line_blank and item.next != null) {
                        nl.tight = false;
                        break;
                    }

                    var subit = item.first_child;
                    while (subit) |subitem| {
                        if (subitem.endsWithBlankLine() and (item.next != null or subitem.next != null)) {
                            nl.tight = false;
                            break;
                        }
                        subit = subitem.next;
                    }

                    if (!nl.tight) {
                        break;
                    }

                    it = item.next;
                }
            },
            else => {},
        }

        return parent;
    }

    fn postprocessTextNodes(self: *Parser) !void {
        var stack = try std.ArrayList(*nodes.AstNode).initCapacity(self.allocator, 1);
        defer stack.deinit();
        var children = std.ArrayList(*nodes.AstNode).init(self.allocator);
        defer children.deinit();

        try stack.append(self.root);

        while (stack.popOrNull()) |node| {
            var nch = node.first_child;

            while (nch) |n| {
                var this_bracket = false;

                while (true) {
                    switch (n.data.value) {
                        .Text => |*root| {
                            var ns = n.next orelse {
                                try self.postprocessTextNode(n, root);
                                break;
                            };

                            switch (ns.data.value) {
                                .Text => |adj| {
                                    const old_len = root.len;
                                    root.* = try self.allocator.realloc(root.*, old_len + adj.len);
                                    std.mem.copy(u8, root.*[old_len..], adj);
                                    ns.detachDeinit();
                                },
                                else => {
                                    try self.postprocessTextNode(n, root);
                                    break;
                                },
                            }
                        },
                        .Link, .Image => {
                            this_bracket = true;
                            break;
                        },
                        else => break,
                    }
                }

                if (!this_bracket) {
                    try children.append(n);
                }

                nch = n.next;
            }

            while (children.popOrNull()) |child| try stack.append(child);
        }
    }

    fn postprocessTextNode(self: *Parser, node: *nodes.AstNode, text: *[]u8) !void {
        if (self.options.extensions.autolink) {
            try AutolinkProcessor.init(self.allocator, text).process(node);
        }
    }

    fn resolveReferenceLinkDefinitions(self: *Parser, content: *std.ArrayList(u8)) !bool {
        var seeked: usize = 0;
        var pos: usize = undefined;
        var seek = content.items;

        while (seek.len > 0 and seek[0] == '[' and try self.parseReferenceInline(seek, &pos)) {
            seek = seek[pos..];
            seeked += pos;
        }

        try content.replaceRange(0, seeked, "");

        return !strings.isBlank(content.items);
    }

    fn parseReferenceInline(self: *Parser, content: []const u8, pos: *usize) !bool {
        var subj = inlines.Subject.init(self.allocator, &self.refmap, &self.options, &self.special_chars, &self.skip_chars, content);
        defer subj.deinit();

        var lab = if (subj.linkLabel()) |l| lab: {
            if (l.len == 0)
                return false;
            break :lab l;
        } else return false;

        if (subj.peekChar() orelse 0 != ':')
            return false;

        subj.pos += 1;
        subj.spnl();

        var url: []const u8 = undefined;
        var match_len: usize = undefined;
        if (!inlines.Subject.manualScanLinkUrl(subj.input[subj.pos..], &url, &match_len))
            return false;
        subj.pos += match_len;

        const beforetitle = subj.pos;
        subj.spnl();
        const title_search: ?usize = if (subj.pos == beforetitle)
            null
        else
            try scanners.linkTitle(subj.input[subj.pos..]);
        const title = if (title_search) |title_match| title: {
            const t = subj.input[subj.pos .. subj.pos + title_match];
            subj.pos += title_match;
            break :title try self.allocator.dupe(u8, t);
        } else title: {
            subj.pos = beforetitle;
            break :title &[_]u8{};
        };
        defer self.allocator.free(title);

        subj.skipSpaces();
        if (!subj.skipLineEnd()) {
            if (title.len > 0) {
                subj.pos = beforetitle;
                subj.skipSpaces();
                if (!subj.skipLineEnd()) {
                    return false;
                }
            } else {
                return false;
            }
        }

        var normalized = try strings.normalizeLabel(self.allocator, lab);
        if (normalized.len > 0) {
            // refmap takes ownership of `normalized'.
            const result = try subj.refmap.getOrPut(normalized);
            if (!result.found_existing) {
                result.value_ptr.* = Reference{
                    .url = try strings.cleanUrl(self.allocator, url),
                    .title = try strings.cleanTitle(self.allocator, title),
                };
            } else {
                self.allocator.free(normalized);
            }
        }

        pos.* = subj.pos;
        return true;
    }

    fn processInlines(self: *Parser) !void {
        try self.processInlinesNode(self.root);
    }

    fn processInlinesNode(self: *Parser, node: *nodes.AstNode) inlines.ParseError!void {
        var it = node.descendantsIterator();
        while (it.next()) |descendant| {
            if (descendant.data.value.containsInlines()) {
                try self.parseInlines(descendant);
            }
        }
    }

    fn parseInlines(self: *Parser, node: *nodes.AstNode) inlines.ParseError!void {
        var content = strings.rtrim(node.data.content.items);
        var subj = inlines.Subject.init(self.allocator, &self.refmap, &self.options, &self.special_chars, &self.skip_chars, content);
        defer subj.deinit();
        while (try subj.parseInline(node)) {}
        try subj.processEmphasis(null);
        while (subj.popBracket()) {}
    }

    pub fn advanceOffset(self: *Parser, line: []const u8, in_count: usize, columns: bool) void {
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

    fn parseNodeItemPrefix(self: *Parser, line: []const u8, container: *nodes.AstNode, nl: *const nodes.NodeList) bool {
        if (self.indent >= nl.marker_offset + nl.padding) {
            self.advanceOffset(line, nl.marker_offset + nl.padding, true);
            return true;
        } else if (self.blank and container.first_child != null) {
            const offset = self.first_nonspace - self.offset;
            self.advanceOffset(line, offset, false);
            return true;
        }
        return false;
    }

    const CodeBlockPrefixParseResult = enum {
        DoNotContinue,
        NoMatch,
        Match,
    };

    fn parseCodeBlockPrefix(self: *Parser, line: []const u8, container: *nodes.AstNode) !CodeBlockPrefixParseResult {
        const ncb = switch (container.data.value) {
            .CodeBlock => |i| i,
            else => unreachable,
        };

        if (!ncb.fenced) {
            if (self.indent >= CODE_INDENT) {
                self.advanceOffset(line, CODE_INDENT, true);
                return .Match;
            } else if (self.blank) {
                const offset = self.first_nonspace - self.offset;
                self.advanceOffset(line, offset, false);
                return .Match;
            }
            return .NoMatch;
        }

        const matched = if (self.indent <= 3 and line[self.first_nonspace] == ncb.fence_char)
            (try scanners.closeCodeFence(line[self.first_nonspace..])) orelse 0
        else
            0;

        if (matched >= ncb.fence_length) {
            self.advanceOffset(line, matched, false);
            self.current = (try self.finalize(container)).?;
            return .DoNotContinue;
        }

        var i = ncb.fence_offset;
        while (i > 0 and strings.isSpaceOrTab(line[self.offset])) : (i -= 1) {
            self.advanceOffset(line, 1, true);
        }

        return .Match;
    }

    fn parseHtmlBlockPrefix(self: *Parser, t: u8) bool {
        return switch (t) {
            1, 2, 3, 4, 5 => true,
            6, 7 => !self.blank,
            else => unreachable,
        };
    }

    fn parseListMarker(line: []const u8, input_pos: usize, interrupts_paragraph: bool, matched: *usize, nl: *nodes.NodeList) bool {
        var pos = input_pos;
        var c = line[pos];
        const startpos = pos;

        if (c == '*' or c == '-' or c == '+') {
            pos += 1;
            if (!ascii.isSpace(line[pos])) {
                return false;
            }

            if (interrupts_paragraph) {
                var i = pos;
                while (strings.isSpaceOrTab(line[i])) : (i += 1) {}
                if (line[i] == '\n') {
                    return false;
                }
            }

            matched.* = pos - startpos;
            nl.* = .{
                .list_type = .Bullet,
                .marker_offset = 0,
                .padding = 0,
                .start = 1,
                .delimiter = .Period,
                .bullet_char = c,
                .tight = false,
            };
            return true;
        }

        if (ascii.isDigit(c)) {
            var start: usize = 0;
            var digits: u8 = 0;

            while (digits < 9 and ascii.isDigit(line[pos])) {
                start = (10 * start) + (line[pos] - '0');
                pos += 1;
                digits += 1;
            }

            if (interrupts_paragraph and start != 1) {
                return false;
            }

            c = line[pos];
            if (c != '.' and c != ')') {
                return false;
            }

            pos += 1;

            if (!ascii.isSpace(line[pos])) {
                return false;
            }

            if (interrupts_paragraph) {
                var i = pos;
                while (strings.isSpaceOrTab(line[i])) : (i += 1) {}
                if (strings.isLineEndChar(line[i])) {
                    return false;
                }
            }

            matched.* = pos - startpos;
            nl.* = .{
                .list_type = .Ordered,
                .marker_offset = 0,
                .padding = 0,
                .start = start,
                .delimiter = if (c == '.')
                    .Period
                else
                    .Paren,
                .bullet_char = 0,
                .tight = false,
            };
            return true;
        }

        return false;
    }

    fn listsMatch(list_data: *const nodes.NodeList, item_data: *const nodes.NodeList) bool {
        return list_data.list_type == item_data.list_type and list_data.delimiter == item_data.delimiter and list_data.bullet_char == item_data.bullet_char;
    }
};

fn expectMarkdownHTML(options: Options, markdown: []const u8, html: []const u8) !void {
    var output = try main.testMarkdownToHtml(options, markdown);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(html, output);
}

test "convert simple emphases" {
    try expectMarkdownHTML(.{},
        \\hello, _world_ __world__ ___world___ *_world_* **_world_** *__world__*
        \\
        \\this is `yummy`
        \\
    ,
        \\<p>hello, <em>world</em> <strong>world</strong> <em><strong>world</strong></em> <em><em>world</em></em> <strong><em>world</em></strong> <em><strong>world</strong></em></p>
        \\<p>this is <code>yummy</code></p>
        \\
    );
}
test "smart quotes" {
    try expectMarkdownHTML(.{ .parse = .{ .smart = true } }, "\"Hey,\" she said. \"What's 'up'?\"\n", "<p>“Hey,” she said. “What’s ‘up’?”</p>\n");
}
test "handles EOF without EOL" {
    try expectMarkdownHTML(.{}, "hello", "<p>hello</p>\n");
}
test "accepts multiple lines" {
    try expectMarkdownHTML(.{}, "hello\nthere\n", "<p>hello\nthere</p>\n");
    try expectMarkdownHTML(.{ .render = .{ .hard_breaks = true } }, "hello\nthere\n", "<p>hello<br />\nthere</p>\n");
}
test "smart hyphens" {
    try expectMarkdownHTML(.{ .parse = .{ .smart = true } }, "hyphen - en -- em --- four ---- five ----- six ------ seven -------\n", "<p>hyphen - en – em — four –– five —– six —— seven —––</p>\n");
}
test "handles tabs" {
    try expectMarkdownHTML(.{}, "\tfoo\tbaz\t\tbim\n", "<pre><code>foo\tbaz\t\tbim\n</code></pre>\n");
    try expectMarkdownHTML(.{}, "  \tfoo\tbaz\t\tbim\n", "<pre><code>foo\tbaz\t\tbim\n</code></pre>\n");
    try expectMarkdownHTML(.{}, "  - foo\n\n\tbar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n");
    try expectMarkdownHTML(.{}, "#\tFoo\n", "<h1>Foo</h1>\n");
    try expectMarkdownHTML(.{}, "*\t*\t*\t\n", "<hr />\n");
}
test "escapes" {
    try expectMarkdownHTML(.{}, "\\## foo\n", "<p>## foo</p>\n");
}
test "setext heading override pointy" {
    try expectMarkdownHTML(.{}, "<a title=\"a lot\n---\nof dashes\"/>\n", "<h2>&lt;a title=&quot;a lot</h2>\n<p>of dashes&quot;/&gt;</p>\n");
}
test "fenced code blocks" {
    try expectMarkdownHTML(.{}, "```\n<\n >\n```\n", "<pre><code>&lt;\n &gt;\n</code></pre>\n");
    try expectMarkdownHTML(.{}, "````\naaa\n```\n``````\n", "<pre><code>aaa\n```\n</code></pre>\n");
}
test "html blocks" {
    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\_world_.
        \\</pre>
    ,
        \\<p><em>world</em>.
        \\</pre></p>
        \\
    );

    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\<table><tr><td>
        \\<pre>
        \\**Hello**,
        \\
        \\_world_.
        \\</pre>
        \\</td></tr></table>
    ,
        \\<table><tr><td>
        \\<pre>
        \\**Hello**,
        \\<p><em>world</em>.
        \\</pre></p>
        \\</td></tr></table>
        \\
    );

    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\<DIV CLASS="foo">
        \\
        \\*Markdown*
        \\
        \\</DIV>
    ,
        \\<DIV CLASS="foo">
        \\<p><em>Markdown</em></p>
        \\</DIV>
        \\
    );

    try expectMarkdownHTML(.{ .render = .{ .unsafe = true } },
        \\<pre language="haskell"><code>
        \\import Text.HTML.TagSoup
        \\
        \\main :: IO ()
        \\main = print $ parseTags tags
        \\</code></pre>
        \\okay
        \\
    ,
        \\<pre language="haskell"><code>
        \\import Text.HTML.TagSoup
        \\
        \\main :: IO ()
        \\main = print $ parseTags tags
        \\</code></pre>
        \\<p>okay</p>
        \\
    );
}
test "links" {
    try expectMarkdownHTML(.{}, "[foo](/url)\n", "<p><a href=\"/url\">foo</a></p>\n");
    try expectMarkdownHTML(.{}, "[foo](/url \"title\")\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n");
}
test "link reference definitions" {
    try expectMarkdownHTML(.{}, "[foo]: /url \"title\"\n\n[foo]\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n");
    try expectMarkdownHTML(.{}, "[foo]: /url\\bar\\*baz \"foo\\\"bar\\baz\"\n\n[foo]\n", "<p><a href=\"/url%5Cbar*baz\" title=\"foo&quot;bar\\baz\">foo</a></p>\n");
}
test "tables" {
    try expectMarkdownHTML(.{ .extensions = .{ .table = true } },
        \\| foo | bar |
        \\| --- | --- |
        \\| baz | bim |
        \\
    ,
        \\<table>
        \\<thead>
        \\<tr>
        \\<th>foo</th>
        \\<th>bar</th>
        \\</tr>
        \\</thead>
        \\<tbody>
        \\<tr>
        \\<td>baz</td>
        \\<td>bim</td>
        \\</tr>
        \\</tbody>
        \\</table>
        \\
    );
}
test "strikethroughs" {
    try expectMarkdownHTML(.{ .extensions = .{ .strikethrough = true } }, "Hello ~world~ there.\n", "<p>Hello <del>world</del> there.</p>\n");
}
test "images" {
    try expectMarkdownHTML(.{}, "[![moon](moon.jpg)](/uri)\n", "<p><a href=\"/uri\"><img src=\"moon.jpg\" alt=\"moon\" /></a></p>\n");
}
test "autolink" {
    try expectMarkdownHTML(.{ .extensions = .{ .autolink = true } }, "www.commonmark.org\n", "<p><a href=\"http://www.commonmark.org\">www.commonmark.org</a></p>\n");
    try expectMarkdownHTML(.{ .extensions = .{ .autolink = true } }, "http://commonmark.org\n", "<p><a href=\"http://commonmark.org\">http://commonmark.org</a></p>\n");
    try expectMarkdownHTML(.{ .extensions = .{ .autolink = true } }, "foo@bar.baz\n", "<p><a href=\"mailto:foo@bar.baz\">foo@bar.baz</a></p>\n");
}
test "header anchors" {
    try expectMarkdownHTML(.{ .render = .{ .header_anchors = true } },
        \\# Hi.
        \\## Hi 1.
        \\### Hi.
        \\#### Hello.
        \\##### Hi.
        \\###### Hello.
        \\# Isn't it grand?
        \\
    ,
        \\<h1><a href="#hi" id="hi"></a>Hi.</h1>
        \\<h2><a href="#hi-1" id="hi-1"></a>Hi 1.</h2>
        \\<h3><a href="#hi-2" id="hi-2"></a>Hi.</h3>
        \\<h4><a href="#hello" id="hello"></a>Hello.</h4>
        \\<h5><a href="#hi-3" id="hi-3"></a>Hi.</h5>
        \\<h6><a href="#hello-1" id="hello-1"></a>Hello.</h6>
        \\<h1><a href="#isnt-it-grand" id="isnt-it-grand"></a>Isn't it grand?</h1>
        \\
    );
}
