const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

pub fn Ast(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: *mem.Allocator,
        data: T,

        parent: ?*Self = null,
        prev: ?*Self = null,
        next: ?*Self = null,
        first_child: ?*Self = null,
        last_child: ?*Self = null,

        pub fn create(allocator: *mem.Allocator, data: T) !*Self {
            var obj = try allocator.create(Self);
            obj.* = .{
                .allocator = allocator,
                .data = data,
            };
            return obj;
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
            var it = self.first_child;
            while (it) |child| {
                var next = child.next;
                child.deinit();
                it = next;
            }
            self.allocator.destroy(self);
        }

        pub fn append(self: *Self, child: *Self) void {
            child.detach();
            child.parent = self;

            if (self.last_child) |last_child| {
                child.prev = last_child;
                assert(last_child.next == null);
                last_child.next = child;
            } else {
                assert(self.first_child == null);
                self.first_child = child;
            }
            self.last_child = child;
        }

        pub fn insertAfter(self: *Self, sibling: *Self) void {
            sibling.detach();
            sibling.parent = self.parent;
            sibling.prev = self;
            if (self.next) |next| {
                assert(next.prev.? == self);
                next.prev = sibling;
                sibling.next = next;
            } else if (self.parent) |parent| {
                assert(parent.last_child.? == self);
                parent.last_child = sibling;
                sibling.next = null;
            }
            self.next = sibling;
        }

        pub fn detach(self: *Self) void {
            if (self.next) |next| {
                next.prev = self.prev;
            } else if (self.parent) |parent| {
                parent.last_child = self.prev;
            }

            if (self.prev) |prev| {
                prev.next = self.next;
            } else if (self.parent) |parent| {
                parent.first_child = self.next;
            }

            self.parent = null;
            self.prev = null;
            self.next = null;

            self.deinit();
        }

        pub fn detachDeinit(self: *Self) void {
            self.detach();
            self.deinit();
        }

        pub fn lastChildIsOpen(self: *Self) bool {
            if (self.last_child) |n| {
                return n.data.open;
            }
            return false;
        }

        pub const ReverseChildrenIterator = struct {
            next_value: ?*Self,

            pub fn next(self: *@This()) ?*Self {
                var to_return = self.next_value;
                if (to_return) |n| {
                    self.next_value = n.prev;
                }
                return to_return;
            }
        };

        pub fn reverseChildrenIterator(self: *Self) ReverseChildrenIterator {
            return .{ .next_value = self.last_child };
        }

        pub fn validate(self: *Self, noisy: bool) void {
            if (noisy) report(self, 0);
            self.validateOne(null, 1, noisy);
        }

        pub fn validateOne(self: *Self, parent: ?*Self, indent: usize, noisy: bool) void {
            assert(self.parent == parent);
            var it = self.first_child;
            var prev: ?*Self = null;

            while (it) |child| {
                if (noisy) report(child, indent);
                assert(child.parent == self);
                assert(child.prev == prev);
                child.validateOne(self, indent + 1, noisy);
                prev = child;
                it = child.next;
            }

            assert(self.last_child == prev);
        }

        pub fn report(self: *Self, indent: usize) void {
            var fill_string: [128]u8 = [_]u8{0} ** 128;
            var i: usize = 0;
            while (i < indent * 4) : (i += 1)
                fill_string[i] = ' ';
            std.debug.print("{}analysing: {*} ({})\n", .{ fill_string, self, @tagName(self.data.value) });
            std.debug.print("{}    parent: {*} ({})\n", .{ fill_string, self.parent, if (self.parent) |n| @tagName(n.data.value) else "" });
            std.debug.print("{}      prev: {*} ({})\n", .{ fill_string, self.prev, if (self.prev) |n| @tagName(n.data.value) else "" });
            std.debug.print("{}      first_child: {*} ({})\n", .{ fill_string, self.first_child, if (self.first_child) |n| @tagName(n.data.value) else "" });
            std.debug.print("{}      last_child: {*} ({})\n", .{ fill_string, self.last_child, if (self.last_child) |n| @tagName(n.data.value) else "" });
            std.debug.print("{}      next: {*} ({})\n", .{ fill_string, self.next, if (self.next) |n| @tagName(n.data.value) else "" });
        }
    };
}

pub const Node = struct {
    value: NodeValue,
    start_line: u32 = 0,

    content: std.ArrayList(u8),
    open: bool = true,
    last_line_blank: bool = false,

    fn deinit(self: *Node) void {
        self.content.deinit();
        self.value.deinit();
    }
};

pub const AstNode = Ast(Node);

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
    // Table
    // TableRow
    // TableCell
    Text: std.ArrayList(u8),
    // TaskItem
    SoftBreak,
    LineBreak,
    Code: std.ArrayList(u8),
    HtmlInline: std.ArrayList(u8),
    Emph,
    Strong,
    Strikethrough,
    Link: NodeLink,
    Image: NodeLink,
    // FootnoteReference

    fn deinit(self: *NodeValue) void {
        switch (self.*) {
            .Text, .HtmlInline, .Code => |content| {
                content.deinit();
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
            else => false,
        };
    }

    pub fn containsInlines(self: NodeValue) bool {
        return switch (self) {
            .Paragraph, .Heading => true,
            else => false,
        };
    }

    pub fn block(self: NodeValue) bool {
        return switch (self) {
            .Document, .BlockQuote, .List, .Item, .CodeBlock, .HtmlBlock, .Paragraph, .Heading, .ThematicBreak => true,
            else => false,
        };
    }

    pub fn text(self: NodeValue) ?[]const u8 {
        return switch (self) {
            .Text => |t| t.span(),
            else => null,
        };
    }

    pub fn text_mut(self: *NodeValue) ?*std.ArrayList(u8) {
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
