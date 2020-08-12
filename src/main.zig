const std = @import("std");

fn Ast(comptime T: type) type {
    return struct {
        content: T,

        parent: ?*@This() = null,
        prev: ?*@This() = null,
        next: ?*@This() = null,
        first_child: ?*@This() = null,
        last_child: ?*@This() = null,
    };
}

const Node = struct {
    value: NodeValue,
    start_line: u32,

    content: []u8,
    open: bool,
    last_line_blank: bool,
};

const NodeValue = union(enum) {
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

const NodeHeading = struct {
    level: u32,
    setext: bool,
};

const Parser = struct {
    allocator: *std.mem.Allocator,
    root: *Ast(Node),
    current: *Ast(Node),
    line_number: u32,
    offset: usize,
    column: usize,
    first_nonspace: usize,
    first_nonspace_column: usize,
    indent: usize,
    blank: bool,
    partially_consumed_tab: bool,
    last_line_length: usize,

    fn feed(self: Parser, s: []const u8) void {}
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var root = Ast(Node){
        .content = Node{
            .value = .Document,
            .content = "",
            .start_line = 0,
            .open = true,
            .last_line_blank = false,
        },
    };

    const parser = Parser{
        .allocator = &arena.allocator,
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
    parser.feed("hello, world!\n\nthis is **yummy**!\n");
}
