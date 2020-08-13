const std = @import("std");
const mem = std.mem;
const ast = @import("ast.zig");

const MAX_BACKTICKS = 80;

pub const Subject = struct {
    allocator: *mem.Allocator,
    arena: *mem.Allocator,
    delimiter_arena: *mem.Allocator,

    input: []const u8,

    pos: usize = 0,
    last_delimiter: ?Delimiter = null,
    brackets: std.ArrayList(Bracket),
    backticks: [MAX_BACKTICKS + 1]usize = [_]usize{0} ** (MAX_BACKTICKS + 1),
    scanned_for_backticks: bool = false,
    special_chars: [256]bool = [_]bool{false} ** 256,
    skip_chars: [256]bool = [_]bool{false} ** 256,
    smart_chars: [256]bool = [_]bool{false} ** 256,

    pub fn init(allocator: *mem.Allocator, arena: *mem.Allocator, input: []const u8, delimiter_arena: *mem.Allocator) Subject {
        return .{
            .allocator = allocator,
            .arena = arena,
            .delimiter_arena = delimiter_arena,

            .input = input,
            .brackets = std.ArrayList(Bracket).init(allocator),
        };
    }

    pub fn parseInline(self: *Subject, node: *ast.AstNode) bool {
        unreachable;
    }

    pub fn processEmphasis(self: *Subject, stack_bottom: anytype) void {
        unreachable;
    }

    pub fn popBracket(self: *Subject) bool {
        unreachable;
    }
};

const Bracket = struct {};
const Delimiter = struct {};
