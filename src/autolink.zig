const std = @import("std");
const nodes = @import("nodes.zig");
const strings = @import("strings.zig");

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
                        ':' => {
                            if (try self.urlMatch(i)) |match| {
                                break :blk match;
                            }
                        },
                        'w' => {
                            if (try self.wwwMatch(i)) |match| {
                                break :blk match;
                            }
                        },
                        '@' => {
                            if (try self.emailMatch(i)) |match| {
                                break :blk match;
                            }
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

    fn urlMatch(self: AutolinkProcessor, i: usize) !?Match {
        unreachable;
    }
    fn wwwMatch(self: AutolinkProcessor, i: usize) !?Match {
        unreachable;
    }
    fn emailMatch(self: AutolinkProcessor, i: usize) !?Match {
        unreachable;
    }
};
