const std = @import("std");
const Parser = @import("parser.zig").Parser;
const nodes = @import("nodes.zig");
const scanners = @import("scanners.zig");
const strings = @import("strings.zig");

pub fn matches(allocator: std.mem.Allocator, line: []const u8) !bool {
    const r = try row(allocator, line);
    const result = r != null;
    if (r) |v| freeNested(allocator, v);
    return result;
}

pub fn freeNested(allocator: std.mem.Allocator, v: [][]u8) void {
    for (v) |e|
        allocator.free(e);
    allocator.free(v);
}

fn row(allocator: std.mem.Allocator, line: []const u8) !?[][]u8 {
    const len = line.len;
    var v = std.ArrayList([]u8).init(allocator);
    errdefer freeNested(allocator, v.toOwnedSlice() catch unreachable);
    var offset: usize = 0;

    if (len > 0 and line[0] == '|')
        offset += 1;

    while (true) {
        const cell_matched = (try scanners.tableCell(line[offset..])) orelse 0;
        var pipe_matched = (try scanners.tableCellEnd(line[offset + cell_matched ..])) orelse 0;

        if (cell_matched > 0 or pipe_matched > 0) {
            var cell = try unescapePipes(allocator, line[offset .. offset + cell_matched]);
            strings.trimIt(&cell);
            try v.append(try cell.toOwnedSlice());
        }

        offset += cell_matched + pipe_matched;

        if (pipe_matched == 0) {
            pipe_matched = (try scanners.tableRowEnd(line[offset..])) orelse 0;
            offset += pipe_matched;
        }

        if (!((cell_matched > 0 or pipe_matched > 0) and offset < len)) {
            break;
        }
    }

    if (offset != len or v.items.len == 0) {
        freeNested(allocator, try v.toOwnedSlice());
        return null;
    } else {
        return try v.toOwnedSlice();
    }
}

pub fn tryOpeningBlock(parser: *Parser, container: *nodes.AstNode, line: []const u8, replace: *bool) !?*nodes.AstNode {
    return switch (container.data.value) {
        .Paragraph => try tryOpeningHeader(parser, container, line, replace),
        .Table => |aligns| tryOpeningRow(parser, container, aligns, line, replace),
        else => null,
    };
}

fn tryOpeningHeader(parser: *Parser, container: *nodes.AstNode, line: []const u8, replace: *bool) !?*nodes.AstNode {
    if ((try scanners.tableStart(line[parser.first_nonspace..])) == null) {
        replace.* = false;
        return container;
    }

    const header_row = (try row(parser.allocator, container.data.content.items)) orelse {
        replace.* = false;
        return container;
    };
    defer freeNested(parser.allocator, header_row);

    const marker_row = (try row(parser.allocator, line[parser.first_nonspace..])).?;
    defer freeNested(parser.allocator, marker_row);

    if (header_row.len != marker_row.len) {
        replace.* = false;
        return container;
    }

    var alignments = try parser.allocator.alloc(nodes.TableAlignment, marker_row.len);
    errdefer parser.allocator.free(alignments);

    for (marker_row, 0..) |cell, i| {
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

    const table = try nodes.AstNode.create(parser.allocator, .{
        .value = .{ .Table = alignments },
        .start_line = parser.line_number,
        .content = std.ArrayList(u8).init(parser.allocator),
    });
    container.append(table);

    const header = try parser.addChild(table, .{ .TableRow = .Header });
    for (header_row) |header_str| {
        var header_cell = try parser.addChild(header, .TableCell);
        try header_cell.data.content.appendSlice(header_str);
    }

    const offset = line.len - 1 - parser.offset;
    parser.advanceOffset(line, offset, false);

    replace.* = true;
    return table;
}

fn tryOpeningRow(parser: *Parser, container: *nodes.AstNode, aligns: []nodes.TableAlignment, line: []const u8, replace: *bool) !?*nodes.AstNode {
    if (parser.blank)
        return null;

    const this_row = (try row(parser.allocator, line[parser.first_nonspace..])).?;
    defer freeNested(parser.allocator, this_row);
    const new_row = try parser.addChild(container, .{ .TableRow = .Body });

    var i: usize = 0;
    while (i < @min(aligns.len, this_row.len)) : (i += 1) {
        var cell = try parser.addChild(new_row, .TableCell);
        try cell.data.content.appendSlice(this_row[i]);
    }

    while (i < aligns.len) : (i += 1) {
        _ = try parser.addChild(new_row, .TableCell);
    }

    const offset = line.len - 1 - parser.offset;
    parser.advanceOffset(line, offset, false);

    replace.* = false;
    return new_row;
}

fn unescapePipes(allocator: std.mem.Allocator, string: []const u8) !std.ArrayList(u8) {
    var v = try std.ArrayList(u8).initCapacity(allocator, string.len);

    for (string, 0..) |c, i| {
        if (c == '\\' and i + 1 < string.len and string[i + 1] == '|') {
            continue;
        } else {
            try v.append(c);
        }
    }

    return v;
}
