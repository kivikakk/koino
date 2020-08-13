const std = @import("std");

pub fn Ast(comptime T: type) type {
    return struct {
        data: T,

        parent: ?*@This() = null,
        prev: ?*@This() = null,
        next: ?*@This() = null,
        first_child: ?*@This() = null,
        last_child: ?*@This() = null,

        pub fn lastChildIsOpen(self: @This()) bool {
            if (self.last_child) |n| {
                return n.data.open;
            }
            return false;
        }
    };
}

pub const Node = struct {
    value: NodeValue,
    start_line: u32,

    content: std.ArrayList(u8),
    open: bool,
    last_line_blank: bool,
};

pub const AstNode = Ast(Node);

pub const NodeValue = union(enum) {
    Document,
    BlockQuote,
    // List
    // Item
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
    // Table
    // TableRow
    // TableCell
    Text: []u8,
    // TaskItem
    SoftBreak,
    LineBreak,
    Code: []u8,
    // HtmlInline
    Emph,
    Strong,
    Strikethrough,
    // Link
    // Image
    // FootnoteReference

    pub fn acceptsLines(self: NodeValue) bool {
        return switch (self) {
            .Paragraph, .Heading, .CodeBlock => true,
            else => false,
        };
    }
};

pub const NodeHtmlBlock = struct {
    block_type: u8,
    literal: []u8,
};

pub const NodeCodeBlock = struct {
    fenced: bool,
    fence_char: u8,
    fence_length: usize,
    fence_offset: usize,
    info: []u8,
    literal: []u8,
};

pub const NodeHeading = struct {
    level: u32,
    setext: bool,
};
