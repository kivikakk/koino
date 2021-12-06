const std = @import("std");
const mem = std.mem;
const ast = @import("ast.zig");

pub const Node = struct {
    value: NodeValue,
    start_line: u32 = 0,

    content: std.ArrayList(u8),
    open: bool = true,
    last_line_blank: bool = false,

    pub fn deinit(self: *Node, allocator: mem.Allocator) void {
        self.content.deinit();
        self.value.deinit(allocator);
    }
};

pub const AstNode = ast.Ast(Node);

pub const NodeValue = union(enum) {
    Document,
    BlockQuote,
    List: NodeList,
    Item: NodeList,
    // DescriptionList
    // DescriptionItem
    // DescriptionTerm
    // DescriptionDetails
    CodeBlock: NodeCodeBlock,
    HtmlBlock: NodeHtmlBlock,
    Paragraph,
    Heading: NodeHeading,
    ThematicBreak,
    // FootnoteDefinition
    Table: []TableAlignment,
    TableRow: TableHeader,
    TableCell,
    Text: []u8,
    // TaskItem
    SoftBreak,
    LineBreak,
    Code: []u8,
    HtmlInline: []u8,
    Emph,
    Strong,
    Strikethrough,
    Link: NodeLink,
    Image: NodeLink,
    // FootnoteReference

    pub fn deinit(self: *NodeValue, allocator: mem.Allocator) void {
        switch (self.*) {
            .Text, .HtmlInline, .Code => |content| {
                allocator.free(content);
            },
            .CodeBlock => |ncb| {
                if (ncb.info) |info| {
                    allocator.free(info);
                }
                ncb.literal.deinit();
            },
            .HtmlBlock => |nhb| {
                nhb.literal.deinit();
            },
            .Table => |aligns| {
                allocator.free(aligns);
            },
            .Link, .Image => |nl| {
                allocator.free(nl.title);
                allocator.free(nl.url);
            },
            else => {},
        }
    }

    pub fn acceptsLines(self: NodeValue) bool {
        return switch (self) {
            .Paragraph, .Heading, .CodeBlock => true,
            else => false,
        };
    }

    pub fn canContainType(self: NodeValue, child: NodeValue) bool {
        if (child == .Document) {
            return false;
        }

        return switch (self) {
            .Document, .BlockQuote, .Item => child.block() and switch (child) {
                .Item => false,
                else => true,
            },
            .List => switch (child) {
                .Item => true,
                else => false,
            },
            .Paragraph, .Heading, .Emph, .Strong, .Link, .Image => !child.block(),
            .Table => switch (child) {
                .TableRow => true,
                else => false,
            },
            .TableRow => switch (child) {
                .TableCell => true,
                else => false,
            },
            .TableCell => switch (child) {
                .Text, .Code, .Emph, .Strong, .Link, .Image, .Strikethrough, .HtmlInline => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn containsInlines(self: NodeValue) bool {
        return switch (self) {
            .Paragraph, .Heading, .TableCell => true,
            else => false,
        };
    }

    pub fn block(self: NodeValue) bool {
        return switch (self) {
            .Document, .BlockQuote, .List, .Item, .CodeBlock, .HtmlBlock, .Paragraph, .Heading, .ThematicBreak, .Table, .TableRow, .TableCell => true,
            else => false,
        };
    }

    pub fn text(self: NodeValue) ?[]const u8 {
        return switch (self) {
            .Text => |t| t,
            else => null,
        };
    }

    pub fn text_mut(self: *NodeValue) ?*[]u8 {
        return switch (self.*) {
            .Text => |*t| t,
            else => null,
        };
    }
};

pub const NodeLink = struct {
    url: []u8,
    title: []u8,
};

pub const ListType = enum {
    Bullet,
    Ordered,
};

pub const ListDelimType = enum {
    Period,
    Paren,
};

pub const NodeList = struct {
    list_type: ListType,
    marker_offset: usize,
    padding: usize,
    start: usize,
    delimiter: ListDelimType,
    bullet_char: u8,
    tight: bool,
};

pub const NodeHtmlBlock = struct {
    block_type: u8,
    literal: std.ArrayList(u8),
};

pub const NodeCodeBlock = struct {
    fenced: bool,
    fence_char: u8,
    fence_length: usize,
    fence_offset: usize,
    info: ?[]u8,
    literal: std.ArrayList(u8),
};

pub const NodeHeading = struct {
    level: u8 = 0,
    setext: bool = false,
};

pub const AutolinkType = enum {
    URI,
    Email,
};

pub const TableAlignment = enum {
    None,
    Left,
    Center,
    Right,
};

pub const TableHeader = enum {
    Header,
    Body,
};
