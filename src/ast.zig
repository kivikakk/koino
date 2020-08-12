pub fn Ast(comptime T: type) type {
    return struct {
        content: T,

        parent: ?*@This() = null,
        prev: ?*@This() = null,
        next: ?*@This() = null,
        first_child: ?*@This() = null,
        last_child: ?*@This() = null,
    };
}

pub const Node = struct {
    value: NodeValue,
    start_line: u32,

    content: []u8,
    open: bool,
    last_line_blank: bool,
};

pub const NodeValue = union(enum) {
    Document,
    BlockQuote,
    // List
    // Item
    // DescriptionList
    // DescriptionItem
    // DescriptionTerm
    // DescriptionDetails
    // CodeBlock
    // HtmlBlock
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
};

pub const NodeHeading = struct {
    level: u32,
    setext: bool,
};
