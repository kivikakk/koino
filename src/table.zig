const Parser = @import("parser.zig").Parser;
const nodes = @import("nodes.zig");
const scanners = @import("scanners.zig");

pub fn matches(line: []const u8) bool {
    return row(line) != null;
}

fn row(line: []const u8) ?[][]u8 {
    unreachable;
}

pub fn tryOpeningBlock(parser: *Parser, container: *nodes.AstNode, line: []const u8, replace: *bool) ?*nodes.AstNode {
    return switch (container.data.value) {
        .Paragraph => tryOpeningHeader(parser, container, line, replace),
        .Table => |aligns| tryOpeningRow(parser, container, aligns, line, replace),
        else => null,
    };
}

fn tryOpeningHeader(parser: *Parser, container: *nodes.AstNode, line: []const u8, replace: *bool) ?*nodes.AstNode {
    if (scanners.tableStart(line[parser.first_nonspace..]) == null) {
        replace.* = false;
        return container;
    }

    const header_row = row(container.data.content) orelse {
        replace.* = false;
        return container;
    };

    const marker_row = row(line[parser.first_nonspace..]).?;

    if (header_row.len != marker_row.len) {
        replace.*=false;
        return container;
    }

    var alignments: [_]nodes.TableAlignment
}

fn tryOpeningRow(parser: *Parser, container: *nodes.AstNode, aligns: []nodes.TableAlignment, line: []const u8, replace: *bool) ?*nodes.AstNode {
    unreachable;
}
