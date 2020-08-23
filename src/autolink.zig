const std = @import("std");
const nodes = @import("nodes.zig");
const strings = @import("strings.zig");
const ctype = @import("ctype.zig");
const zunicode = @import("zunicode");

pub const AutolinkProcessor = struct {
    allocator: *std.mem.Allocator,
    text: *[]u8,

    pub fn init(allocator: *std.mem.Allocator, text: *[]u8) AutolinkProcessor {
        return .{
            .allocator = allocator,
            .text = text,
        };
    }

    const Match = struct {
        post: *nodes.AstNode,
        reverse: usize,
        skip: usize,
    };

    pub fn process(self: AutolinkProcessor, node: *nodes.AstNode) !void {
        const len = self.text.len;
        var i: usize = 0;

        while (i < len) {
            var post_org: ?Match = blk: {
                while (i < len) : (i += 1) {
                    switch (self.text.*[i]) {
                        'w' => if (try self.wwwMatch(i)) |match| {
                            break :blk match;
                        },
                        ':' => if (try self.urlMatch(i)) |match| {
                            break :blk match;
                        },
                        '@' => if (try self.emailMatch(i)) |match| {
                            break :blk match;
                        },
                        else => {},
                    }
                }
                break :blk null;
            };

            if (post_org) |org| {
                i -= org.reverse;
                unreachable;
            }
        }
    }

    const WWW_DELIMS = strings.createMap("*_~([");
    fn wwwMatch(self: AutolinkProcessor, i: usize) !?Match {
        if (i > 0 and !ctype.isspace(self.text.*[i - 1]) and !WWW_DELIMS[self.text.*[i - 1]]) {
            return null;
        }

        if (!std.mem.startsWith(u8, self.text.*[i..], "www.")) {
            return null;
        }

        var link_end = (try checkDomain(self.text.*[i..], false)) orelse return null;

        while (i + link_end < self.text.len and
            !ctype.isspace(self.text.*[i + link_end])) : (link_end += 1)
        {}

        link_end = autolinkDelim(self.text.*[i..], link_end);

        var url = try std.ArrayList(u8).initCapacity(self.allocator, 7 + link_end);
        try url.appendSlice("http://");
        try url.appendSlice(self.text.*[i .. link_end + i]);

        var inl = try self.makeInline(.{
            .Link = .{
                .url = url.toOwnedSlice(),
                .title = try self.allocator.alloc(u8, 0),
            },
        });
        inl.append(try self.makeInline(.{
            .Text = self.allocator.dupe(u8, self.text.*[i .. link_end + i]),
        }));
        return Match{
            .post = inl,
            .reverse = 0,
            .skip = link_end,
        };
    }

    fn urlMatch(self: AutolinkProcessor, i: usize) !?Match {
        unreachable;
    }

    fn emailMatch(self: AutolinkProcessor, i: usize) !?Match {
        unreachable;
    }

    fn checkDomain(data: []const u8, allow_short: bool) !?usize {
        var np: usize = 0;
        var uscore1: usize = 0;
        var uscore2: usize = 0;

        var view = try std.unicode.Utf8View.init(data);
        var it = view.iterator();

        var last_i = it.i;
        while (it.nextCodepoint()) |c| {
            if (c == '_') {
                uscore2 += 1;
            } else if (c == '.') {
                uscore1 = uscore2;
                uscore2 = 0;
                np += 1;
            } else if (!isValidHostchar(c) and c != '-') {
                if (uscore1 == 0 and uscore2 == 0 and np > 0) {
                    return last_i;
                }
                return null;
            }
            last_i = it.i;
        }

        if (uscore1 > 0 or uscore2 > 0) {
            return null;
        } else if (allow_short or np > 0) {
            return data.len;
        } else {
            return null;
        }
    }

    fn isValidHostchar(c: u21) bool {
        return !zunicode.isSpace(c) and !zunicode.isPunct(c);
    }

    const LINK_END_ASSORTMENT = strings.createMap("?!.,:*_~'\"");
    fn autolinkDelim(data: []const u8, in_link_end: usize) usize {
        var link_end = in_link_end;

        for (data[0..link_end]) |c, i| {
            // X
            unreachable;
        }
        return link_end;
    }

    fn makeInline(self: AutolinkProcessor, value: nodes.NodeValue) !*nodes.AstNode {
        return nodes.AstNode.create(self.allocator, .{
            .value = value,
            .content = std.ArrayList(u8).init(self.allocator),
        });
    }
};
