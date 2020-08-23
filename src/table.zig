const std = @import("std");
const Parser = @import("parser.zig").Parser;
const nodes = @import("nodes.zig");
const scanners = @import("scanners.zig");

pub fn matches(line: []const u8) bool {
    return row(line) != null;
}

fn row(line: []const u8) ?[][]u8 {
    unreachable;
}

pub fn tryOpeningBlock(parser: *Parser, container: *nodes.AstNode, line: []const u8, replace: *bool) !?*nodes.AstNode {
    return switch (container.data.value) {
        .Paragraph => try tryOpeningHeader(parser, container, line, replace),
        .Table => |aligns| tryOpeningRow(parser, container, aligns, line, replace),
        else => null,
    };
}

fn tryOpeningHeader(parser: *Parser, container: *nodes.AstNode, line: []const u8, replace: *bool) !?*nodes.AstNode {
    if (scanners.tableStart(line[parser.first_nonspace..]) == null) {
        replace.* = false;
        return container;
    }

    const header_row = row(container.data.content.items) orelse {
        replace.* = false;
        return container;
    };

    const marker_row = row(line[parser.first_nonspace..]).?;

    if (header_row.len != marker_row.len) {
        replace.* = false;
        return container;
    }

    var alignments = try parser.allocator.alloc(nodes.TableAlignment, marker_row.len);
    errdefer parser.allocator.free(alignments);

    for (marker_row) |cell, i| {
        const left = cell.len > 0 and cell[0] == ':';
        const right = cell.len > 0 and cell[cell.len - 1] == ':';
        alignments[i] = if (left and right)
            nodes.TableAlignment.Center
        else if (left)
            nodes.TableAlignment.Left
        else if (right)
            nodes.TableAlignment.Right
        else
            nodes.TableAlignment.None;
    }

    var table = try nodes.AstNode.create(parser.allocator, .{
        .value = .{ .Table = alignments },
        .start_line = parser.line_number,
        .content = std.ArrayList(u8).init(parser.allocator),
    });
    container.append(table);

    var header = try parser.addChild(table, .{ .TableRow = .Header });
    for (header_row) |header_str| {
        var header_cell = try parser.addChild(header, .TableCell);
        try header_cell.data.content.appendSlice(header_str);
    }

    const offset = line.len - 1 - parser.offset;
    parser.advanceOffset(line, offset, false);

    replace.* = true;
    return table;
}

fn tryOpeningRow(parser: *Parser, container: *nodes.AstNode, aligns: []nodes.TableAlignment, line: []const u8, replace: *bool) ?*nodes.AstNode {
    unreachable;
}
