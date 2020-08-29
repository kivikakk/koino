const std = @import("std");
const ascii = std.ascii;
const assert = std.debug.assert;
const nodes = @import("nodes.zig");
const strings = @import("strings.zig");
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
                node.insertAfter(org.post);
                if (i + org.skip < len) {
                    const remain = self.text.*[i + org.skip ..];
                    assert(remain.len > 0);
                    org.post.insertAfter(try self.makeInline(.{ .Text = try self.allocator.dupe(u8, remain) }));
                }
                self.text.* = self.allocator.shrink(self.text.*, i);
                return;
            }
        }
    }

    const WWW_DELIMS = strings.createMap("*_~([");
    fn wwwMatch(self: AutolinkProcessor, i: usize) !?Match {
        if (i > 0 and !ascii.isSpace(self.text.*[i - 1]) and !WWW_DELIMS[self.text.*[i - 1]]) {
            return null;
        }

        if (!std.mem.startsWith(u8, self.text.*[i..], "www.")) {
            return null;
        }

        var link_end = (try checkDomain(self.text.*[i..], false)) orelse return null;

        while (i + link_end < self.text.len and
            !ascii.isSpace(self.text.*[i + link_end])) : (link_end += 1)
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
            .Text = try self.allocator.dupe(u8, self.text.*[i .. link_end + i]),
        }));
        return Match{
            .post = inl,
            .reverse = 0,
            .skip = link_end,
        };
    }

    const SCHEMES = [_][]const u8{ "http", "https", "ftp" };
    fn urlMatch(self: AutolinkProcessor, i: usize) !?Match {
        const size = self.text.len;

        if (size - i < 4 or self.text.*[i + 1] != '/' or self.text.*[i + 2] != '/') {
            return null;
        }

        var rewind: usize = 0;
        while (rewind < i and
            ascii.isAlpha(self.text.*[i - rewind - 1])) : (rewind += 1)
        {}

        if (!scheme_matched: {
            for (SCHEMES) |scheme| {
                if (size - i + rewind >= scheme.len and std.mem.eql(u8, self.text.*[i - rewind .. i], scheme)) {
                    break :scheme_matched true;
                }
            }
            break :scheme_matched false;
        }) {
            return null;
        }

        var link_end = (try checkDomain(self.text.*[i + 3 ..], true)) orelse return null;

        while (link_end < size - i and !ascii.isSpace(self.text.*[i + link_end])) : (link_end += 1) {}

        link_end = autolinkDelim(self.text.*[i..], link_end);

        const url = self.text.*[i - rewind .. i + link_end];

        var inl = try self.makeInline(.{
            .Link = .{
                .url = try self.allocator.dupe(u8, url),
                .title = try self.allocator.alloc(u8, 0),
            },
        });
        inl.append(try self.makeInline(.{ .Text = try self.allocator.dupe(u8, url) }));
        return Match{
            .post = inl,
            .reverse = rewind,
            .skip = rewind + link_end,
        };
    }

    const EMAIL_OK_SET = strings.createMap(".+-_");
    fn emailMatch(self: AutolinkProcessor, i: usize) !?Match {
        const size = self.text.len;

        var rewind: usize = 0;
        var ns: usize = 0;
        while (rewind < i) {
            const c = self.text.*[i - rewind - 1];
            if (ascii.isAlNum(c) or EMAIL_OK_SET[c]) {
                rewind += 1;
                continue;
            }

            if (c == '/') {
                ns += 1;
            }

            break;
        }

        if (rewind == 0 or ns > 0) {
            return null;
        }

        var link_end: usize = 0;
        var nb: usize = 0;
        var np: usize = 0;

        while (link_end < size - i) {
            const c = self.text.*[i + link_end];

            if (ascii.isAlNum(c)) {
                // empty
            } else if (c == '@') {
                nb += 1;
            } else if (c == '.' and link_end < size - i - 1 and ascii.isAlNum(self.text.*[i + link_end + 1])) {
                np += 1;
            } else if (c != '-' and c != '_') {
                break;
            }

            link_end += 1;
        }

        if (link_end < 2 or nb != 1 or np == 0 or (!ascii.isAlpha(self.text.*[i + link_end - 1]) and self.text.*[i + link_end - 1] != '.')) {
            return null;
        }

        link_end = autolinkDelim(self.text.*[i..], link_end);

        var url = try std.ArrayList(u8).initCapacity(self.allocator, 7 + link_end - rewind);
        try url.appendSlice("mailto:");
        try url.appendSlice(self.text.*[i - rewind .. link_end + i]);

        var inl = try self.makeInline(.{
            .Link = .{
                .url = url.toOwnedSlice(),
                .title = try self.allocator.alloc(u8, 0),
            },
        });
        inl.append(try self.makeInline(.{ .Text = try self.allocator.dupe(u8, self.text.*[i - rewind .. link_end + i]) }));
        return Match{
            .post = inl,
            .reverse = rewind,
            .skip = rewind + link_end,
        };
    }

    fn checkDomain(data: []const u8, allow_short: bool) !?usize {
        var np: usize = 0;
        var uscore1: usize = 0;
        var uscore2: usize = 0;

        var view = std.unicode.Utf8View.initUnchecked(data);
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
            if (c == '<') {
                link_end = i;
                break;
            }
        }

        while (link_end > 0) {
            const cclose = data[link_end - 1];
            const copen: ?u8 = if (cclose == ')') '(' else null;

            if (LINK_END_ASSORTMENT[cclose]) {
                link_end -= 1;
            } else if (cclose == ';') {
                var new_end = link_end - 2;

                while (new_end > 0 and
                    ascii.isAlNum(data[new_end])) : (new_end -= 1)
                {}

                if (new_end < link_end - 2 and data[new_end] == '&') {
                    link_end = new_end;
                } else {
                    link_end -= 1;
                }
            } else if (copen) |c| {
                var opening: usize = 0;
                var closing: usize = 0;
                for (data[0..link_end]) |b| {
                    if (b == c) {
                        opening += 1;
                    } else if (b == cclose) {
                        closing += 1;
                    }
                }

                if (closing <= opening) break;

                link_end -= 1;
            } else {
                break;
            }
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
